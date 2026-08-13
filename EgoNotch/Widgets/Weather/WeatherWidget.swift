import SwiftUI
import CoreLocation
import Observation

/// Phase 4 — current temperature + short hourly strip via Open-Meteo (free,
/// no key). Location comes from CoreLocation; denied → manual city from
/// Settings (geocoded via Open-Meteo's geocoding API); neither → hint tile.
/// Fetches only when the tile appears and the cache is older than 15 min.
final class WeatherWidget: NotchWidget {
    let id = "weather"
    let displayName = "Weather"
    let icon = "cloud.sun"
    let tileSize: WidgetTileSize = .small
    let tab: NotchTab = .home

    let service = WeatherService()

    func makeExpandedView() -> AnyView {
        AnyView(WeatherTileView(service: service))
    }
}

struct HourlyPoint: Equatable {
    let date: Date
    let temperature: Double
    let code: Int
}

@Observable
final class WeatherService: NSObject, CLLocationManagerDelegate {
    private(set) var temperature: Double?
    private(set) var weatherCode = 0
    private(set) var hourly: [HourlyPoint] = []
    private(set) var placeName: String?
    private(set) var needsCity = false      // no location AND no manual city
    private(set) var isLoading = false

    @ObservationIgnored private var lastFetch: Date?
    @ObservationIgnored private var fetchedCity: String?   // "" = automatic location
    @ObservationIgnored private var manager: CLLocationManager?

    private static let cacheTTL: TimeInterval = 15 * 60

    /// Entry point — called from the tile's onAppear.
    func refreshIfStale() {
        let city = SettingsStore.shared.weatherCity.trimmingCharacters(in: .whitespaces)
        // A changed (or cleared) manual city invalidates the cache immediately.
        if let lastFetch, Date().timeIntervalSince(lastFetch) < Self.cacheTTL,
           fetchedCity == city { return }
        guard !isLoading else { return }

        if !city.isEmpty {
            Task { await fetchForCity(city) }
            return
        }
        startLocation()
    }

    private func startLocation() {
        if manager == nil {
            let m = CLLocationManager()
            m.delegate = self
            m.desiredAccuracy = kCLLocationAccuracyKilometer
            manager = m
        }
        switch manager!.authorizationStatus {
        case .authorized, .authorizedAlways:
            manager!.requestLocation()
        case .notDetermined:
            manager!.requestWhenInUseAuthorization()
        default:
            needsCity = true
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, let manager = self.manager else { return }
            switch manager.authorizationStatus {
            case .authorized, .authorizedAlways:
                self.needsCity = false
                manager.requestLocation()
            case .denied, .restricted:
                self.needsCity = SettingsStore.shared.weatherCity.isEmpty
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let coord = loc.coordinate
        Task { @MainActor [weak self] in
            await self?.fetch(latitude: coord.latitude, longitude: coord.longitude, name: nil)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.needsCity = SettingsStore.shared.weatherCity.isEmpty
        }
    }

    // MARK: - Open-Meteo

    private func fetchForCity(_ city: String) async {
        isLoading = true
        defer { isLoading = false }
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1")]
        guard let (data, _) = try? await URLSession.shared.data(from: comps.url!),
              let decoded = try? JSONDecoder().decode(GeocodeResponse.self, from: data),
              let hit = decoded.results?.first else {
            needsCity = true
            return
        }
        await fetch(latitude: hit.latitude, longitude: hit.longitude, name: hit.name)
    }

    private func fetch(latitude: Double, longitude: Double, name: String?) async {
        isLoading = true
        defer { isLoading = false }
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "hourly", value: "temperature_2m,weather_code"),
            .init(name: "forecast_hours", value: "8"),
            .init(name: "timezone", value: "auto"),   // local wall-clock hours, not GMT
        ]
        guard let (data, _) = try? await URLSession.shared.data(from: comps.url!),
              let decoded = try? JSONDecoder().decode(ForecastResponse.self, from: data) else {
            return
        }
        temperature = decoded.current.temperature_2m
        weatherCode = decoded.current.weather_code
        hourly = zip(zip(decoded.hourly.time, decoded.hourly.temperature_2m),
                     decoded.hourly.weather_code).compactMap { pair, code in
            let (time, temp) = pair
            guard let date = Self.parseLocalTime(time) else { return nil }
            return HourlyPoint(date: date, temperature: temp, code: code)
        }
        placeName = name
        needsCity = false
        lastFetch = Date()
        fetchedCity = SettingsStore.shared.weatherCity.trimmingCharacters(in: .whitespaces)
    }

    nonisolated private static func parseLocalTime(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = .current
        return f.date(from: s)
    }

    static func symbol(for code: Int) -> String {
        switch code {
        case 0: "sun.max"
        case 1, 2: "cloud.sun"
        case 3: "cloud"
        case 45, 48: "cloud.fog"
        case 51...67: "cloud.drizzle"
        case 71...77: "cloud.snow"
        case 80...82: "cloud.rain"
        case 85, 86: "cloud.snow"
        case 95...99: "cloud.bolt.rain"
        default: "cloud"
        }
    }

    private struct GeocodeResponse: Decodable {
        struct Hit: Decodable { let name: String; let latitude: Double; let longitude: Double }
        let results: [Hit]?
    }

    private struct ForecastResponse: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double]
            let weather_code: [Int]
        }
        let current: Current
        let hourly: Hourly
    }
}

struct WeatherTileView: View {
    var service: WeatherService

    var body: some View {
        Group {
            if service.needsCity {
                VStack(alignment: .leading, spacing: 6) {
                    Chip(text: "No location", variant: .neutral)
                    Text("Set a city in Settings → General")
                        .font(Ego.font(10))
                        .foregroundStyle(Ego.textMute)
                }
            } else if let temp = service.temperature {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: WeatherService.symbol(for: service.weatherCode))
                            .font(.system(size: 22))
                            .foregroundStyle(Ego.text)
                        Text("\(Int(temp.rounded()))°")
                            .font(.system(size: 26, weight: .bold))
                            .egoDigits()
                            .foregroundStyle(Ego.text)
                        if let place = service.placeName {
                            Text(place)
                                .font(Ego.font(10))
                                .foregroundStyle(Ego.textMute)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        ForEach(service.hourly.prefix(6), id: \.date) { point in
                            VStack(spacing: 2) {
                                Text(point.date, format: .dateTime.hour())
                                    .font(Ego.font(8))
                                    .foregroundStyle(Ego.textMute)
                                Image(systemName: WeatherService.symbol(for: point.code))
                                    .font(.system(size: 9))
                                    .foregroundStyle(Ego.textMute)
                                Text("\(Int(point.temperature.rounded()))°")
                                    .font(Ego.font(9))
                                    .egoDigits()
                                    .foregroundStyle(Ego.text)
                            }
                        }
                    }
                }
            } else {
                Text(service.isLoading ? "Loading weather…" : "Weather unavailable")
                    .font(Ego.font(11))
                    .foregroundStyle(Ego.textMute)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { service.refreshIfStale() }
    }
}
