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

    var body: some View {
        SwitcherWindowList(
            entries: entries, selectedRow: selectedRow, scrollTarget: scrollTarget,
            scrollRequestID: scrollRequestID,
            rowHeight: rowHeight, selectionInsetX: selectionInsetX,
            selectionInsetY: selectionInsetY, selectionCornerRadius: selectionCornerRadius,
            onCommit: onCommit
        )
        .padding(8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
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
