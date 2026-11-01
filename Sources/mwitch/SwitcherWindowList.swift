import Cocoa

/// Native row virtualization and minimal scrolling, independent of SwiftUI
/// view identity. Selection is revealed after layout, including on panel reuse.
final class SwitcherWindowListView: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    let table = NSTableView()
    private var entries: [WindowEntry] = []
    private var selectedRow: Int?
    private var pendingReveal: Int?
    private var onCommit: (Int) -> Void = { _ in }
    private let selectionInsetX: CGFloat
    private let selectionInsetY: CGFloat
    private let selectionCornerRadius: CGFloat

    init(rowHeight: CGFloat = 48, selectionInsetX: CGFloat = 8,
         selectionInsetY: CGFloat = 4, selectionCornerRadius: CGFloat = 10) {
        self.selectionInsetX = selectionInsetX
        self.selectionInsetY = selectionInsetY
        self.selectionCornerRadius = selectionCornerRadius
        super.init(frame: .zero)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        autohidesScrollers = true

        // Automatic table styling adds vertical insets beyond the row heights,
        // creating a tiny overflow in a panel sized to fit its rows exactly.
        table.style = .plain
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = rowHeight
        table.intercellSpacing = .zero
        table.focusRingType = .none
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.allowsTypeSelect = false
        table.refusesFirstResponder = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.action = #selector(clickedRow)
        documentView = table
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func render(entries: [WindowEntry], selectedRow: Int?, scrollTarget: Int?,
                onCommit: @escaping (Int) -> Void) {
        let changed = self.entries.count != entries.count || zip(self.entries, entries).contains {
            $0.cgWindowID != $1.cgWindowID || $0.appName != $1.appName ||
            $0.title != $1.title || $0.appIcon !== $1.appIcon
        }
        let previous = self.selectedRow
        self.entries = entries
        self.onCommit = onCommit
        self.selectedRow = selectedRow.flatMap { entries.indices.contains($0) ? $0 : nil }
        if changed { table.reloadData() }
        let selection = self.selectedRow.map { IndexSet(integer: $0) } ?? IndexSet()
        if table.selectedRowIndexes != selection {
            table.selectRowIndexes(selection, byExtendingSelection: false)
        }
        // Only refresh cells whose selected text colors changed.
        if !changed, previous != self.selectedRow {
            for row in [previous, self.selectedRow].compactMap({ $0 }) {
                if let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? WindowCell {
                    cell.configure(entries[row], selected: row == self.selectedRow)
                }
            }
        }
        if let scrollTarget, entries.indices.contains(scrollTarget) {
            pendingReveal = scrollTarget
            needsLayout = true
        } else {
            pendingReveal = nil
        }
    }

    override func layout() {
        super.layout()
        guard let row = pendingReveal else { return }
        pendingReveal = nil
        // AppKit does nothing if the whole row is already visible, and moves
        // only as far as needed otherwise. Fixed row heights work before a
        // distant row's reusable cell exists.
        table.scrollRowToVisible(row)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("window-cell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? WindowCell ?? WindowCell()
        cell.identifier = identifier
        cell.configure(entries[row], selected: row == selectedRow)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        WindowRow(insetX: selectionInsetX, insetY: selectionInsetY, radius: selectionCornerRadius)
    }

    @objc private func clickedRow() {
        let row = table.clickedRow
        guard entries.indices.contains(row) else { return }
        onCommit(row)
    }
}

private final class WindowRow: NSTableRowView {
    private let insetX: CGFloat
    private let insetY: CGFloat
    private let radius: CGFloat

    init(insetX: CGFloat, insetY: CGFloat, radius: CGFloat) {
        self.insetX = insetX
        self.insetY = insetY
        self.radius = radius
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: insetX, dy: insetY),
                     xRadius: radius, yRadius: radius).fill()
    }
}

private final class WindowCell: NSTableCellView {
    private var entry: WindowEntry?
    private var selected = false
    private static let font = NSFont.systemFont(ofSize: 16)
    private static let fallbackIcon = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
    private static let titleStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ entry: WindowEntry, selected: Bool) {
        self.entry = entry
        self.selected = selected
        setAccessibilityLabel("\(entry.appName), \(entry.title)")
        toolTip = entry.title
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let entry else { return }
        let textY = (bounds.height - 21) / 2
        (entry.appIcon ?? Self.fallbackIcon)?.draw(
            in: NSRect(x: 20, y: (bounds.height - 28) / 2, width: 28, height: 28),
            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
        )
        (entry.title as NSString).draw(
            in: NSRect(x: 60, y: textY, width: max(0, bounds.width - 80), height: 21),
            withAttributes: [
                .font: Self.font, .paragraphStyle: Self.titleStyle,
                .foregroundColor: selected ? NSColor.white : NSColor.labelColor
            ]
        )
    }
}
