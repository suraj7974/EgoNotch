import AppKit
import Observation
import UserNotifications

/// Custom countdown timer — behaves like a real kitchen timer: set a
/// duration, start, and it RINGS (system sound ×3) plus posts a notification
/// on completion. Anchored to ContinuousClock so sleep/pauses never drift.
@Observable
final class TimerEngine {
    private(set) var duration: TimeInterval = 5 * 60
    private(set) var remaining: TimeInterval = 5 * 60
    private(set) var isRunning = false

    @ObservationIgnored private var end: ContinuousClock.Instant?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    func add(_ seconds: TimeInterval) {
        guard !isRunning else { return }
        duration = min(duration + seconds, 24 * 3600)
        remaining = duration
    }

    func clear() {
        guard !isRunning else { return }
        duration = 0
        remaining = 0
    }

    func startPause() {
        if isRunning {
            pause()
        } else {
            guard remaining > 0 else { return }
            start()
        }
    }

    func reset() {
        end = nil
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
        remaining = duration
        publishMenuBar()
    }

    private func start() {
        isRunning = true
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

    private func pause() {
        if let end {
            remaining = max(Self.seconds(ContinuousClock.now.duration(to: end)), 0)
        }
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
        remaining = duration      // re-arm like a real timer
        publishMenuBar()
        ring()

        let content = UNMutableNotificationContent()
        content.title = "Timer done"
        content.body = "\(Self.format(duration)) is up"
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Ring like a real timer: three chimes.
    private func ring() {
        Task {
            for _ in 0..<3 {
                (NSSound(named: NSSound.Name("Glass"))?.copy() as? NSSound)?.play()
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }

    private func publishMenuBar() {
        var info: [String: Any] = ["source": "timer"]
        if isRunning { info["text"] = Self.format(remaining) }
        NotificationCenter.default.post(name: .egoMenuBarText, object: nil, userInfo: info)
    }

    static func seconds(_ d: Duration) -> TimeInterval {
        TimeInterval(d.components.seconds) + TimeInterval(d.components.attoseconds) / 1e18
    }

    static func format(_ t: TimeInterval) -> String {
        let s = max(Int(t.rounded()), 0)
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// Stopwatch — pure anchor math, zero background cost: elapsed is computed
/// from the start instant, so nothing ticks except the visible display.
@Observable
final class Stopwatch {
    private(set) var isRunning = false
    /// Bumped on start/pause/reset so SwiftUI re-reads `elapsed`.
    private(set) var generation = 0

    @ObservationIgnored private var accumulated: TimeInterval = 0
    @ObservationIgnored private var startedAt: ContinuousClock.Instant?

    var elapsed: TimeInterval {
        accumulated + (startedAt.map { TimerEngine.seconds($0.duration(to: .now)) } ?? 0)
    }

    func startPause() {
        if isRunning {
            accumulated = elapsed
            startedAt = nil
            isRunning = false
        } else {
            startedAt = ContinuousClock.now
            isRunning = true
        }
        generation += 1
    }

    func reset() {
        accumulated = 0
        startedAt = nil
        isRunning = false
        generation += 1
    }

    static func format(_ t: TimeInterval) -> String {
        let total = max(t, 0)
        let s = Int(total)
        let cs = Int((total - Double(s)) * 100)
        if s >= 3600 {
            return String(format: "%d:%02d:%02d.%02d", s / 3600, (s % 3600) / 60, s % 60, cs)
        }
        return String(format: "%02d:%02d.%02d", s / 60, s % 60, cs)
    }
}
