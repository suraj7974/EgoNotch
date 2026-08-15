import Foundation

/// Static facts about this build, for the About pane and anywhere else that
/// wants to name the app.
enum AppInfo {
    static let name = "EgoNotch"
    static let owner = "Suraj Patel"
    static let portfolio = "surajpatel.me"
    static let portfolioURL = URL(string: "https://surajpatel.me")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0"
    }
}
