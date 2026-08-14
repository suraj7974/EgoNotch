import SwiftUI

/// Non-home tabs: tiles in fixed rows (2 units per row; .small = 1,
/// .wide = 2). No scrolling — content is sized to fit the short panel.
struct WidgetGridView: View {
    private var ui = PanelUIState.shared

    var body: some View {
        // @Observable reads → auto-invalidates on toggle and tab switch.
        let widgets = WidgetRegistry.enabled.filter {
            $0.tab == ui.selectedTab && $0.makeExpandedView() != nil
        }
        Group {
            if widgets.isEmpty {
                EmptyGridView()
            } else {
                Grid(horizontalSpacing: Ego.gridSpacing, verticalSpacing: Ego.gridSpacing) {
                    ForEach(Array(packRows(widgets).enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(row, id: \.id) { widget in
                                WidgetTile(widget: widget)
                                    .gridCellColumns(widget.tileSize == .wide ? 2 : 1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func packRows(_ widgets: [any NotchWidget]) -> [[any NotchWidget]] {
        var rows: [[any NotchWidget]] = []
        var row: [any NotchWidget] = []
        var units = 0
        for w in widgets {
            let u = w.tileSize == .wide ? 2 : 1
            if units + u > 2 {
                rows.append(row)
                row = []
                units = 0
            }
            row.append(w)
            units += u
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }
}

struct WidgetTile: View {
    let widget: any NotchWidget

    var body: some View {
        if widget.wantsTileChrome {
            VStack(alignment: .leading, spacing: 8) {
                ColumnHeader(title: widget.displayName,
                             appName: widget.companionAppName,
                             openApp: { widget.openCompanionApp() })
                widget.makeExpandedView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .egoCard()
        } else {
            // Edge-to-edge: the widget owns every pixel of the tile.
            widget.makeExpandedView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct EmptyGridView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("No modules enabled")
                .font(Ego.font(12, .medium))
                .foregroundStyle(Ego.textMute)
            Text("Turn them on in Settings")
                .font(Ego.font(10))
                .foregroundStyle(Ego.textMute.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
