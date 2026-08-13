import Foundation

/// The three UI states of the notch panel.
enum NotchState: Equatable {
    case closed
    case hover
    case expanded
}

/// How the panel goes from closed to expanded.
enum ExpansionBehavior: Equatable {
    case hoverWithDwell(TimeInterval)
    case clickToExpand
}
