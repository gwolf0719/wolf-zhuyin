import Cocoa
import WolfEngine

/// 「學習紀錄」視窗：列出輸入法從使用者打字學到的東西（選字、用詞、打錯），可以搜尋、刪掉不要的。
/// 一定要開在輸入法自己的行程裡、用同一份 `Stores`：紀錄平常放在記憶體，另一個行程改檔案會被蓋掉。
final class LearnedWindow: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    static var shared: LearnedWindow?

    var terminatesOnClose = false
    private let stores: Preferences.Stores
    private let window: NSWindow
    private let kinds = NSSegmentedControl(labels: ["選字", "用詞", "打錯"], trackingMode: .selectOne, target: nil, action: nil)
    private let search = NSSearchField()
    private let table = DeletableTableView()
    private let summary = NSTextField(labelWithString: "")
    private let removeButton = NSButton(title: "刪除選取的", target: nil, action: nil)
    private var all: [LearnedEntry] = []
    private var shown: [LearnedEntry] = []

    private static let headers: [LearnedEntry.Kind: [String]] = [
        .phrase: ["讀音", "選的字詞", "狀態"],
        .history: ["前面是", "接著打", "次數"],
        .typo: ["打錯的按鍵", "原本想打", "次數"],
    ]
    private static let explanations: [LearnedEntry.Kind: String] = [
        .phrase: "你在選字窗選過的字詞。同一個讀音下，最近選的那個會優先出現。",
        .history: "你打過的詞序，用來預測接下來的內容。出現 2 次以上才會拿來預測。",
        .typo: "你退格重打、或在選字窗修正過的打錯。帶數字聲調的更正一次就生效，其他要 2 次。",
    ]
    private let explanation = NSTextField(wrappingLabelWithString: "")

    init(stores: Preferences.Stores) {
        self.stores = stores
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        super.init()
        window.title = "狼注音學習紀錄"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 480, height: 360)
        window.center()

        kinds.selectedSegment = 0
        kinds.target = self
        kinds.action = #selector(kindChanged(_:))
        search.placeholderString = "搜尋"
        search.delegate = self
        search.target = self
        search.action = #selector(searchChanged(_:))
        explanation.font = .systemFont(ofSize: 11)
        explanation.textColor = .secondaryLabelColor

        for (index, identifier) in ["left", "right", "count"].enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.width = index == 2 ? 110 : 220
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 24
        table.onDelete = { [weak self] in self?.removeSelected(nil) }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        removeButton.bezelStyle = .rounded
        removeButton.target = self
        removeButton.action = #selector(removeSelected(_:))
        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .secondaryLabelColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let top = NSStackView(views: [kinds, search])
        top.spacing = 12
        let bottom = NSStackView(views: [summary, spacer, removeButton])
        bottom.spacing = 12

        let stack = NSStackView(views: [top, explanation, scroll, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            top.widthAnchor.constraint(equalTo: stack.widthAnchor),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bottom.widthAnchor.constraint(equalTo: stack.widthAnchor),
            search.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
    }

    func show(kind: LearnedEntry.Kind = .phrase) {
        kinds.selectedSegment = kind.rawValue
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private var kind: LearnedEntry.Kind { LearnedEntry.Kind(rawValue: kinds.selectedSegment) ?? .phrase }

    private func reload() {
        all = stores.entries(kind)
        for (column, title) in zip(table.tableColumns, Self.headers[kind]!) { column.title = title }
        explanation.stringValue = Self.explanations[kind]!
        filter()
    }

    private func filter() {
        let query = search.stringValue.trimmingCharacters(in: .whitespaces)
        shown = query.isEmpty ? all : all.filter { $0.left.contains(query) || $0.right.contains(query) }
        table.reloadData()
        table.deselectAll(nil)
        let active = all.filter(\.isActive).count
        summary.stringValue = "共 \(all.count) 筆，其中 \(active) 筆已經在影響打字" + (query.isEmpty ? "" : "；符合搜尋的 \(shown.count) 筆")
        removeButton.isEnabled = false
    }

    @objc private func kindChanged(_ sender: Any?) {
        search.stringValue = ""
        reload()
    }

    @objc private func searchChanged(_ sender: Any?) { filter() }

    func controlTextDidChange(_ notification: Notification) { filter() }

    @objc private func removeSelected(_ sender: Any?) {
        let selected = table.selectedRowIndexes.map { shown[$0] }
        guard !selected.isEmpty else { return }
        selected.forEach(stores.remove)
        reload()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = shown[row]
        let text: String
        switch tableColumn?.identifier.rawValue {
        case "left": text = entry.left
        case "right": text = entry.right
        default:
            if entry.kind == .phrase {
                text = entry.isActive ? "優先採用" : "備用"
            } else {
                text = "\(entry.count) 次" + (entry.isActive ? "" : "（未生效）")
            }
        }
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14)
        label.textColor = entry.isActive ? .labelColor : .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = !table.selectedRowIndexes.isEmpty
    }

    func windowWillClose(_ notification: Notification) {
        stores.flush()
        if terminatesOnClose { NSApp.terminate(nil) }
    }
}

/// 按 Delete 鍵刪除選取的列。
private final class DeletableTableView: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }
}
