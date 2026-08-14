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
    private(set) var eventDays: Set<Int> = []      // days this month with events

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
        eventDays = []
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
            let snapshot = await Task.detached(priority: .utility) {
                Self.fetchSnapshot(from: store)
            }.value
            self?.todaysEvents = snapshot.events
            self?.eventDays = snapshot.days
        }
    }

    nonisolated private static func fetchSnapshot(
        from store: EKEventStore
    ) -> (events: [EventItem], days: Set<Int>) {
        let cal = Calendar.current
        let now = Date()
        let dayStart = cal.startOfDay(for: now)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart),
              let month = cal.dateInterval(of: .month, for: now) else { return ([], []) }

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

        let monthPredicate = store.predicateForEvents(withStart: month.start,
                                                      end: month.end, calendars: nil)
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

struct CalendarCompactView: View {
    var store: CalendarStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
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
                // Month grid up top (the space events used to waste)…
                MonthGrid(eventDays: store.eventDays)
                Spacer(minLength: 0)
                // …and today's events along the bottom.
                eventsFooter
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { store.refresh() }
    }

    private var eventsFooter: some View {
        Group {
            if store.todaysEvents.isEmpty {
                Text("No events today")
                    .font(Ego.font(10))
                    .foregroundStyle(Ego.textMute)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(store.todaysEvents.prefix(2)) { event in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(event.color ?? Ego.accentSoft)
                                .frame(width: 2.5, height: 11)
                            Text(event.title)
                                .font(Ego.font(10, .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(event.start, format: .dateTime.hour().minute())
                                .font(Ego.font(9))
                                .egoDigits()
                                .foregroundStyle(Ego.textMute)
                        }
                    }
                    if store.todaysEvents.count > 2 {
                        Text("+\(store.todaysEvents.count - 2) more")
                            .font(Ego.font(9))
                            .egoDigits()
                            .foregroundStyle(Ego.textMute)
                    }
                }
            }
        }
    }
}

/// Full month: weekday header, every day, dots on days with events, today
/// highlighted.
private struct MonthGrid: View {
    let eventDays: Set<Int>

    /// One flat, uniquely-indexed cell list — leading blanks and day numbers
    /// in a single ForEach so grid identity can never collide.
    private struct Cell: Identifiable {
        let id: Int
        let day: Int?
    }

    var body: some View {
        let cal = Calendar.current
        let now = Date()
        let today = cal.component(.day, from: now)
        let days = Array(cal.range(of: .day, in: .month, for: now) ?? 1..<29)
        let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? now
        let leading = (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7
        let cells = (0..<leading).map { Cell(id: $0, day: nil) }
            + days.enumerated().map { Cell(id: leading + $0.offset, day: $0.element) }
        let symbols = Array(cal.veryShortWeekdaySymbols[(cal.firstWeekday - 1)...]
                            + cal.veryShortWeekdaySymbols[..<(cal.firstWeekday - 1)])
        let columns = Array(repeating: GridItem(.flexible(minimum: 13), spacing: 1), count: 7)

        VStack(alignment: .leading, spacing: 5) {
            Text(now, format: .dateTime.month(.wide).year())
                .font(Ego.font(12, .bold))
                .foregroundStyle(.white)

            HStack(spacing: 1) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(Ego.font(9, .medium))
                        .foregroundStyle(Ego.textMute.opacity(0.65))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(cells) { cell in
                    Group {
                        if let day = cell.day {
                            // Round marker for today — a square badge read
                            // as "boxy" against the airy grid.
                            Text("\(day)")
                                .font(Ego.font(10, day == today ? .bold : .regular))
                                .egoDigits()
                                .foregroundStyle(day == today ? .black : .white.opacity(0.8))
                                .frame(width: 18, height: 18)
                                .background(day == today ? Color.white : .clear, in: Circle())
                                .overlay(alignment: .bottom) {
                                    if eventDays.contains(day), day != today {
                                        Circle()
                                            .fill(Ego.accentSoft)
                                            .frame(width: 3, height: 3)
                                            .offset(y: 1)
                                    }
                                }
                        } else {
                            Color.clear.frame(width: 18, height: 18)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
