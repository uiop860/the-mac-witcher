struct SwitcherSession {
    private(set) var listState = SwitcherListState()
    private(set) var isVisible = false

    var entries: [WindowEntry] { listState.entries }
    var selection: Int { listState.selectedRow ?? -1 }
    var selectedEntry: WindowEntry? {
        entries.indices.contains(selection) ? entries[selection] : nil
    }
    var snapshot: SwitcherPanelSnapshot { listState.snapshot }

    mutating func start(entries: [WindowEntry], reverse: Bool = false) -> SwitcherSessionResult {
        guard !entries.isEmpty else { return .none }
        let initialSelection = reverse ? entries.count - 1 : min(1, entries.count - 1)
        _ = listState.update(entries: entries, selection: initialSelection)
        isVisible = true
        return .render(scrollTarget: listState.selectedRow)
    }

    /// Preserve the current order and selected window across an asynchronous
    /// close/quit. Only confirmed missing windows are removed.
    mutating func refresh(entries incoming: [WindowEntry]) -> SwitcherSessionResult {
        guard isVisible else { return .none }
        let selectedID = selectedEntry?.cgWindowID
        let previousSelection = selection
        var remaining = Dictionary(incoming.map { ($0.cgWindowID, $0) },
                                   uniquingKeysWith: { first, _ in first })
        var refreshed = entries.compactMap { remaining.removeValue(forKey: $0.cgWindowID) }
        for entry in incoming {
            if let new = remaining.removeValue(forKey: entry.cgWindowID) { refreshed.append(new) }
        }
        let next = selectedID.flatMap { id in refreshed.firstIndex { $0.cgWindowID == id } }
            ?? max(0, min(previousSelection, refreshed.count - 1))
        _ = listState.update(entries: refreshed, selection: next)
        if refreshed.isEmpty {
            isVisible = false
            return .dismiss(chosen: nil)
        }
        return .render(scrollTarget: next)
    }

    mutating func perform(_ action: SwitcherPanelAction) -> SwitcherSessionResult {
        switch action {
        case .cancel:
            guard isVisible else { return .none }
            isVisible = false
            return .dismiss(chosen: nil)
        case .commit:
            return commit()
        case .moveSelection(let delta):
            return moveSelection(by: delta)
        case .commitRow(let row):
            guard entries.indices.contains(row) else { return .none }
            _ = listState.selectRow(row)
            return commit()
        }
    }

    private mutating func moveSelection(by delta: Int) -> SwitcherSessionResult {
        guard listState.moveSelection(by: delta) != nil else {
            listState.clearSelection()
            return .render(scrollTarget: nil)
        }
        return .render(scrollTarget: listState.selectedRow)
    }

    private mutating func commit() -> SwitcherSessionResult {
        guard isVisible else { return .none }
        let chosen = entries.indices.contains(selection) ? entries[selection] : nil
        isVisible = false
        return .dismiss(chosen: chosen)
    }
}

enum SwitcherSessionResult: Equatable {
    case none
    case render(scrollTarget: Int?)
    case dismiss(chosen: WindowEntry?)
}
