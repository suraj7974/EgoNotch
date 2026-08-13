import SwiftUI
import EventKit
import Observation

/// Home-strip calendar column (NotchNest style): month, today's events (or
/// "No Events"), and a three-day strip with today highlighted. Access is
/// requested lazily when the column first appears; denial degrades to a hint.
final class CalendarWidget: NotchWidget {
    let id = "calendar"
    let displayName = "Calendar"
    let icon = "calendar"
    let tab: NotchTab = .home

    let store = CalendarStore()
    private var active = false

    func activate() {
        guard !active else { return }
        active = true
        store.start()
    }

    func deactivate() {
        guard active else { return }
        active = false
        store.stop()
    }

    func makeCompactView() -> AnyView? {
        AnyView(CalendarCompactView(store: store))
    }
}

/// Sendable snapshot of an event — EKEvent itself never crosses threads.
struct EventItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: Color?
}

@Observable
final class CalendarStore {
    enum Access { case unknown, granted, denied }

    private(set) var access: Access = .unknown
    private(set) var todaysEvents: [EventItem] = []

    @ObservationIgnored private let eventStore = EKEventStore()
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    func start() {
        // Never prompt at app launch — only reflect the current status here.
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
            refresh()
        case .denied, .restricted, .writeOnly:
            access = .denied
        default:
            access = .unknown
        }
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleRefresh() }
        }
    }

    func stop() {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
        changeObserver = nil
        refreshTask?.cancel()
        refreshTask = nil
        todaysEvents = []
    }

    /// Called when the column appears — first time asks the user.
    func requestAccessIfNeeded() {
        guard access == .unknown else { return }
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else {
            access = EKEventStore.authorizationStatus(for: .event) == .fullAccess
                ? .granted : .denied
            if access == .granted { refresh() }
            return
        }
        eventStore.requestFullAccessToEvents { [weak self] granted, _ in
            Task { @MainActor [weak self] in
                self?.access = granted ? .granted : .denied
                if granted { self?.refresh() }
            }
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func refresh() {
        guard access == .granted else { return }
        nonisolated(unsafe) let store = eventStore
        Task { [weak self] in
            let events = await Task.detached(priority: .utility) {
                Self.fetchToday(from: store)
            }.value
            self?.todaysEvents = events
        }
    }

    nonisolated private static func fetchToday(from store: EKEventStore) -> [EventItem] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: Date())
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                EventItem(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    color: (event.calendar?.cgColor).map { Color(cgColor: $0) }
                )
            }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct CalendarCompactView: View {
    var store: CalendarStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date(), format: .dateTime.month(.abbreviated))
                .font(Ego.font(13, .bold))
                .foregroundStyle(Ego.text)

            switch store.access {
            case .denied:
                Spacer(minLength: 0)
                Button("Enable Calendar") { store.openSystemSettings() }
                    .buttonStyle(.egoSecondary)
                Spacer(minLength: 0)
            case .unknown:
                Spacer(minLength: 0)
                Text("Calendar access…")
                    .font(Ego.font(10))
                    .foregroundStyle(Ego.textMute)
                    .onAppear { store.requestAccessIfNeeded() }
                Spacer(minLength: 0)
            case .granted:
                if store.todaysEvents.isEmpty {
                    Spacer(minLength: 0)
                    Text("No Events")
                        .font(Ego.font(13))
                        .foregroundStyle(Ego.textMute)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer(minLength: 0)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(store.todaysEvents.prefix(2)) { event in
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(event.color ?? Ego.accentSoft)
                                    .frame(width: 3)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(event.title)
                                        .font(Ego.font(11, .semibold))
                                        .foregroundStyle(Ego.text)
                                        .lineLimit(1)
                                    Text(event.start, format: .dateTime.hour().minute())
                                        .font(Ego.font(9))
                                        .egoDigits()
                                        .foregroundStyle(Ego.textMute)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            dayStrip
        }
        .frame(maxHeight: .infinity)
        .onAppear { store.refresh() }
    }

    /// Yesterday · today (highlighted) · tomorrow, NotchNest style.
    private var dayStrip: some View {
        let cal = Calendar.current
        let days = (-1...1).compactMap { cal.date(byAdding: .day, value: $0, to: Date()) }
        return HStack(spacing: 12) {
            ForEach(days, id: \.self) { day in
                let isToday = cal.isDateInToday(day)
                VStack(spacing: 1) {
                    Text(day, format: .dateTime.weekday(.abbreviated))
                        .font(Ego.font(9, isToday ? .semibold : .regular))
                    Text(day, format: .dateTime.day())
                        .font(Ego.font(11, isToday ? .bold : .regular))
                        .egoDigits()
                }
                .foregroundStyle(isToday ? Ego.text : Ego.textMute.opacity(0.7))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(isToday ? Color.white.opacity(0.14) : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
