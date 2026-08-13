import Foundation

/// A source of now-playing state + transport control. Exactly one provider is
/// active at a time (see MediaController). Implementations must be fully
/// event-driven — no polling.
@MainActor
protocol MediaProvider: AnyObject {
    func start()
    func stop()
    func send(_ command: MediaCommand)
}
