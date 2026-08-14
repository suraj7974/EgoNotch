import Foundation

extension Notification.Name {
    /// UI-level requests any decoupled widget view can post; AppDelegate
    /// observes. Lives at app level so deleting a widget folder never breaks
    /// the build.
    static let egoOpenSettings = Notification.Name("EgoNotch.openSettings")
    static let egoCollapseNotch = Notification.Name("EgoNotch.collapseNotch")
    /// Menu-bar countdown text ("text" userInfo key; absent = clear).
    static let egoMenuBarText = Notification.Name("EgoNotch.menuBarTextDidChange")
    /// Re-open the first-launch tour (Settings → About).
    static let egoShowOnboarding = Notification.Name("EgoNotch.showOnboarding")
    /// Global shortcut: open the panel straight on the Terminal tab.
    static let egoToggleTerminal = Notification.Name("EgoNotch.toggleTerminal")
    /// A new track started ("title"/"artist" userInfo) — drives the notch's
    /// transient song-change peek.
    static let egoSongChanged = Notification.Name("EgoNotch.songChanged")
}
