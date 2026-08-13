import AppKit
import Observation
import UserNotifications

/// Pomodoro engine. The 1s tick exists ONLY while a session runs (it must —
/// the menu-bar countdown and closed-notch chip update while the panel is
/// closed); idle state has no timer. Completion posts a notification with the
/// day-streak count; denied notification permission degrades to silence.
@Observable
final class FocusTimer {
    enum Mode: String, CaseIterable, Identifiable {
        case focus, shortBreak, deep
        var id: String { rawValue }

        var title: String {
            switch self {
            case .focus: "Focus"
            case .shortBreak: "Break"
            case .deep: "Deep"
            }
        }

        @MainActor
        var minutes: Int {
            let s = SettingsStore.shared
            switch self {
            case .focus: return s.focusMinutes
            case .shortBreak: return s.breakMinutes
            case .deep: return s.deepMinutes
            }
        }
    }

    private(set) var mode: Mode = .focus
    private(set) var remaining: TimeInterval = 0
    private(set) var isRunning = false
    private(set) var streakDays = 0
    private(set) var sessionsToday = 0

    @ObservationIgnored private var tickTask: Task<Void, Never>?
    /// Target end instant (ContinuousClock advances across machine sleep) —
    /// `remaining` is recomputed from it each tick, so the countdown tracks
    /// real elapsed time instead of counting loop iterations.
    @ObservationIgnored private var end: ContinuousClock.Instant?
    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        streakDays = defaults.integer(forKey: "focus.streakDays")
        sessionsToday = defaults.integer(forKey: "focus.sessionsToday")
        rollStreakForToday(countingCompletion: false)
        remaining = TimeInterval(mode.minutes * 60)
    }

    // MARK: - Controls

    func select(_ newMode: Mode) {
        mode = newMode
        stop()
        remaining = TimeInterval(newMode.minutes * 60)
    }

    func startPause() {
        if isRunning {
            pause()
        } else {
            if remaining <= 0 { remaining = TimeInterval(mode.minutes * 60) }
            start()
        }
    }

    func reset() {
        stop()
        remaining = TimeInterval(mode.minutes * 60)
    }

    private func start() {
        isRunning = true
        requestNotificationAuthorizationOnce()
        end = ContinuousClock.now.advanced(by: .seconds(remaining))
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(100))
                guard !Task.isCancelled, let self, self.isRunning else { return }
                if let end = self.end {
                    self.remaining = max(Self.seconds(ContinuousClock.now.duration(to: end)), 0)
                }
                self.publishMenuBar()
                if self.remaining <= 0 {
                    self.complete()
                    return
                }
            }
        }
        publishMenuBar()
    }

    private static func seconds(_ d: Duration) -> TimeInterval {
        TimeInterval(d.components.seconds) + TimeInterval(d.components.attoseconds) / 1e18
    }

    private func pause() {
        // Preserve the fractional remainder so pause/resume never drifts.
        if let end {
            remaining = max(Self.seconds(ContinuousClock.now.duration(to: end)), 0)
        }
        end = nil
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
        publishMenuBar()
    }

    private func stop() {
        end = nil
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
        publishMenuBar()
    }

    private func complete() {
        end = nil
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
        remaining = 0
        if mode != .shortBreak {
            rollStreakForToday(countingCompletion: true)
        }
        publishMenuBar()
        postCompletionNotification()
    }

    // MARK: - Streaks

    private func rollStreakForToday(countingCompletion: Bool) {
        let cal = Calendar.current
        let last = defaults.object(forKey: "focus.lastCompletion") as? Date
        if let last {
            if cal.isDateInToday(last) {
                // same day — streak unchanged
            } else if cal.isDateInYesterday(last) {
                if countingCompletion { streakDays += 1 }
                sessionsToday = 0
            } else {
                streakDays = countingCompletion ? 1 : 0
                sessionsToday = 0
            }
        } else if countingCompletion {
            streakDays = 1
        }
        if countingCompletion {
            sessionsToday += 1
            defaults.set(Date(), forKey: "focus.lastCompletion")
        }
        defaults.set(streakDays, forKey: "focus.streakDays")
        defaults.set(sessionsToday, forKey: "focus.sessionsToday")
    }

    // MARK: - Notifications

    private func requestNotificationAuthorizationOnce() {
        guard !defaults.bool(forKey: "focus.notifAsked") else { return }
        defaults.set(true, forKey: "focus.notifAsked")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postCompletionNotification() {
        let content = UNMutableNotificationContent()
        content.title = "\(mode.title) complete"
        content.body = "Day streak \(streakDays) · \(sessionsToday) session\(sessionsToday == 1 ? "" : "s") today"
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Formatting

    var display: String { Self.format(remaining) }

    static func format(_ t: TimeInterval) -> String {
        let s = max(Int(t.rounded()), 0)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func publishMenuBar() {
        var info: [String: Any] = ["source": "pomodoro"]
        if isRunning { info["text"] = display }
        NotificationCenter.default.post(name: .egoMenuBarText, object: nil, userInfo: info)
    }
}
