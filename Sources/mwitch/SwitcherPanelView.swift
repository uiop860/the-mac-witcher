import Cocoa
import SwiftUI

struct SwitcherPanelView: View {
    let entries: [WindowEntry]
    let selectedRow: Int?
    let scrollTarget: Int?
    let scrollRequestID: Int
    let rowHeight: CGFloat
    let selectionInsetX: CGFloat
    let selectionInsetY: CGFloat
    let selectionCornerRadius: CGFloat
    let onCommit: (Int) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    static let cornerRadius: CGFloat = 20

    var body: some View {
        SwitcherWindowList(
            entries: entries, selectedRow: selectedRow, scrollTarget: scrollTarget,
            scrollRequestID: scrollRequestID,
            rowHeight: rowHeight, selectionInsetX: selectionInsetX,
            selectionInsetY: selectionInsetY, selectionCornerRadius: selectionCornerRadius,
            onCommit: onCommit
        )
        .padding(8)
        .background {
            panelBackground
        }
    }

    @ViewBuilder
    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        if reduceTransparency {
            shape.fill(Color(nsColor: .windowBackgroundColor))
        } else if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
                .overlay {
                    shape.strokeBorder(Color(nsColor: .separatorColor).opacity(0.25), lineWidth: 1)
                }
        }
    }
}

private struct SwitcherWindowList: NSViewRepresentable {
    let entries: [WindowEntry]
    let selectedRow: Int?
    let scrollTarget: Int?
    let scrollRequestID: Int
    let rowHeight: CGFloat
    let selectionInsetX: CGFloat
    let selectionInsetY: CGFloat
    let selectionCornerRadius: CGFloat
    let onCommit: (Int) -> Void

    func makeNSView(context: Context) -> SwitcherWindowListView {
        SwitcherWindowListView(rowHeight: rowHeight, selectionInsetX: selectionInsetX,
                               selectionInsetY: selectionInsetY,
                               selectionCornerRadius: selectionCornerRadius)
    }

    func updateNSView(_ view: SwitcherWindowListView, context: Context) {
        view.render(entries: entries, selectedRow: selectedRow,
                    scrollTarget: scrollTarget, onCommit: onCommit)
    }
}
