import SwiftUI
import EventKit
import Observation

/// Phase 4 — Today tab: month mini-grid + today's events (EventKit).
/// Denied access degrades to an "enable in Settings" tile; never crashes.
/// The permission request fires lazily when the Today tile first appears.
final class CalendarWidget: NotchWidget {
    let id = "calendar"
    let displayName = "Today"
    let icon = "calendar"
    let tileSize: WidgetTileSize = .wide
    let tab: NotchTab = .today

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

    func makeExpandedView() -> AnyView {
        AnyView(CalendarTileView(store: store))
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
    private(set) var eventDays: Set<Int> = []      // days of the current month with events

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
        // Event-driven, coalesced refresh whenever the calendar DB changes
        // (the store posts bursts of change notifications).
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
        eventDays = []
    }

    /// Called when the Today tile appears — first time asks the user.
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
        // EKEventStore queries are thread-safe; run them off the main actor
        // and hand back only Sendable snapshots (large calendars can stall).
        nonisolated(unsafe) let store = eventStore
        Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                Self.fetchSnapshot(from: store)
            }.value
            guard let self else { return }
            self.todaysEvents = snapshot.events
            self.eventDays = snapshot.days
        }
    }

    nonisolated private static func fetchSnapshot(
        from store: EKEventStore
    ) -> (events: [EventItem], days: Set<Int>) {
        let cal = Calendar.current
        let now = Date()

        let dayStart = cal.startOfDay(for: now)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart),
              let monthRange = cal.dateInterval(of: .month, for: now) else {
            return ([], [])
        }

        let todayPredicate = store.predicateForEvents(withStart: dayStart, end: dayEnd,
                                                      calendars: nil)
        let events = store.events(matching: todayPredicate)
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

        let monthPredicate = store.predicateForEvents(withStart: monthRange.start,
                                                      end: monthRange.end, calendars: nil)
        let days = Set(store.events(matching: monthPredicate)
            .map { cal.component(.day, from: $0.startDate) })

        return (events, days)
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct CalendarTileView: View {
    var store: CalendarStore

    var body: some View {
        switch store.access {
        case .denied:
            HStack(spacing: 10) {
                Chip(text: "No access", variant: .loss)
                Text("Enable Calendar for EgoNotch in System Settings")
                    .font(Ego.font(11))
                    .foregroundStyle(Ego.textMute)
                Spacer()
                Button("Open Settings") { store.openSystemSettings() }
                    .buttonStyle(.egoSecondary)
            }
            .frame(minHeight: 52)
        case .unknown:
            Text("Requesting calendar access…")
                .font(Ego.font(11))
                .foregroundStyle(Ego.textMute)
                .frame(maxWidth: .infinity, minHeight: 52)
                .onAppear { store.requestAccessIfNeeded() }
        case .granted:
            HStack(alignment: .top, spacing: 14) {
                MonthMiniGrid(eventDays: store.eventDays)
                eventsList
            }
            .onAppear { store.refresh() }
        }
    }

    private var eventsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.todaysEvents.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.checkmark")
                        .foregroundStyle(Ego.win)
                    Text("No events today")
                        .font(Ego.font(12))
                        .foregroundStyle(Ego.textMute)
                }
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            } else {
                ForEach(store.todaysEvents.prefix(4)) { event in
                    EventRow(event: event)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EventRow: View {
    let event: EventItem

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color ?? Ego.accentSoft)
                .frame(width: 3.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(Ego.font(12, .semibold))
                    .foregroundStyle(Ego.text)
                    .lineLimit(1)
                Text("\(event.start, format: .dateTime.hour().minute()) – \(event.end, format: .dateTime.hour().minute())")
                    .font(Ego.font(10))
                    .egoDigits()
                    .foregroundStyle(Ego.textMute)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(Ego.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Compact month grid; days with events get a dot, today gets a ring.
private struct MonthMiniGrid: View {
    let eventDays: Set<Int>

    var body: some View {
        let cal = Calendar.current
        let now = Date()
        let today = cal.component(.day, from: now)
        let range = cal.range(of: .day, in: .month, for: now) ?? 1..<31
        let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? now
        // Leading blanks relative to the user's chosen first weekday.
        let firstSlot = (cal.component(.weekday, from: monthStart)
            - cal.firstWeekday + 7) % 7

        VStack(alignment: .leading, spacing: 4) {
            Text(now, format: .dateTime.month(.wide))
                .font(Ego.font(11, .semibold))
                .foregroundStyle(Ego.text)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(18), spacing: 3), count: 7),
                      spacing: 3) {
                ForEach(0..<firstSlot, id: \.self) { _ in Color.clear.frame(height: 16) }
                ForEach(Array(range), id: \.self) { day in
                    Text("\(day)")
                        .font(Ego.font(8.5, day == today ? .bold : .regular))
                        .egoDigits()
                        .foregroundStyle(day == today ? Ego.text : Ego.textMute)
                        .frame(width: 18, height: 16)
                        .background(
                            Circle().strokeBorder(
                                day == today ? Ego.accentSoft : .clear, lineWidth: 1)
                        )
                        .overlay(alignment: .bottom) {
                            if eventDays.contains(day) && day != today {
                                Circle().fill(Ego.accentSoft.opacity(0.8))
                                    .frame(width: 2.5, height: 2.5)
                                    .offset(y: 1)
                            }
                        }
                }
            }
        }
    }
}
