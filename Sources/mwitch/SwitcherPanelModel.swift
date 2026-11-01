struct SwitcherPanelSnapshot {
    var entries: [WindowEntry]
    var selectedRow: Int?

    static let empty = SwitcherPanelSnapshot(entries: [], selectedRow: nil)
}

enum SwitcherPanelAction {
    case cancel
    case commit
    case moveSelection(delta: Int)
    case commitRow(Int)
}
