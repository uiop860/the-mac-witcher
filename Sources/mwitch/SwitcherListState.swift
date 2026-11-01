import Cocoa

/// Window list and keyboard selection for the switcher.
struct SwitcherListState {
    private(set) var entries: [WindowEntry] = []
    private(set) var selectedRow: Int?

    mutating func update(entries: [WindowEntry], selection: Int) -> Int? {
        self.entries = entries
        return selectRow(selection)
    }

    mutating func selectRow(_ row: Int) -> Int? {
        selectedRow = entries.indices.contains(row) ? row : nil
        return selectedRow
    }

    mutating func clearSelection() {
        selectedRow = nil
    }

    mutating func moveSelection(by delta: Int) -> Int? {
        guard !entries.isEmpty else {
            selectedRow = nil
            return nil
        }
        let offset = ((selectedRow ?? 0) + delta % entries.count) % entries.count
        selectedRow = (offset + entries.count) % entries.count
        return selectedRow
    }

    var snapshot: SwitcherPanelSnapshot {
        SwitcherPanelSnapshot(entries: entries, selectedRow: selectedRow)
    }
}
