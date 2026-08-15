import Foundation

/// The UI states of the notch panel.
enum NotchState: Equatable {
    case closed
    /// Transient live activity (e.g. a song change): the collapsed notch
    /// grows a strip below itself to announce something, then returns.
    case peek
    case hover
    case expanded
    /// Ego is listening or answering: a wide, short HUD strip. Distinct from
    /// `.expanded` because it must appear over whatever you were doing and
    /// then hand the panel back to its previous state.
    case assistant
}

/// How the panel goes from closed to expanded.
enum ExpansionBehavior: Equatable {
    case hoverWithDwell(TimeInterval)
    case clickToExpand
}
