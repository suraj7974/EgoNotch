import SwiftUI

/// Composes enabled widgets into the expanded panel. Rows hold 2 units:
/// .small = 1, .wide = 2, packed greedily in registry order.
struct WidgetGridView: View {
    private var ui = PanelUIState.shared

    var body: some View {
        // @Observable reads → auto-invalidates on toggle and tab switch.
        let widgets = WidgetRegistry.enabled.filter { $0.tab == ui.selectedTab }
        Group {
            if widgets.isEmpty {
                EmptyGridView()
            } else {
                Grid(horizontalSpacing: Ego.gridSpacing, verticalSpacing: Ego.gridSpacing) {
                    ForEach(Array(packRows(widgets).enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(row, id: \.id) { widget in
                                WidgetTile(widget: widget, index: fileIndex(of: widget))
                                    .gridCellColumns(widget.tileSize == .wide ? 2 : 1)
                            }
                        }
                    }
                }
                // Ideal height only — the enclosing ScrollView owns overflow.
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func fileIndex(of widget: any NotchWidget) -> Int {
        (WidgetRegistry.all.firstIndex { $0.id == widget.id } ?? 0) + 1
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
    let index: Int
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(index: index, title: widget.displayName)
            widget.makeExpandedView()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .egoCard(hovered: hovered)
        .onHover { over in
            withAnimation(Ego.Motion.spring()) { hovered = over }
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
