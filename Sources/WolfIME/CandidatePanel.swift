import Cocoa

/// 選字窗：游標下方的直式清單，每列「編號 + 候選」。只負責顯示，選取邏輯在引擎的 `Composer`。
final class CandidatePanel: NSPanel {
    static let shared = CandidatePanel()

    private let stack = NSStackView()

    private init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        contentView = background

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
        ])
    }

    override var canBecomeKey: Bool { false }

    /// - Parameter cursor: 組字游標在螢幕上的位置（左下角原點）。
    /// - Parameter cyclesWithTab: 列的是預測，反白的已經套用、按 Tab 換下一個；數字鍵不能選，所以不標數字。
    func show(candidates: [String], highlighted: Int, cyclesWithTab: Bool = false, near cursor: NSRect) {
        let rows = candidates.enumerated().map { index, candidate in
            CandidateRow(label: cyclesWithTab ? "⇥" : "\(index + 1)", text: candidate, isHighlighted: index == highlighted)
        }
        show(rows, near: cursor)
    }

    /// 預測提示：全部列出來，不反白，表示按 Tab 才會採用。標籤就是要按幾下 Tab：⇥、⇥⇥、⇥⇥⇥。
    static let maximumHints = 5
    func show(predictions: [String], near cursor: NSRect) {
        let rows = predictions.prefix(Self.maximumHints).enumerated().map { index, prediction in
            CandidateRow(label: String(repeating: "⇥", count: index + 1), text: prediction, isHighlighted: false, isHint: true)
        }
        show(rows, near: cursor)
    }

    private func show(_ rows: [CandidateRow], near cursor: NSRect) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for row in rows {
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -10).isActive = true
        }
        stack.layoutSubtreeIfNeeded()
        let size = stack.fittingSize

        // 預設放在游標下方；下方放不下就翻到上方，並且不超出螢幕左右。
        let screen = NSScreen.screens.first { $0.frame.contains(cursor.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var origin = NSPoint(x: cursor.minX, y: cursor.minY - size.height - 4)
        if origin.y < visible.minY { origin.y = cursor.maxY + 4 }
        origin.x = max(visible.minX, min(origin.x, visible.maxX - size.width))
        setFrame(NSRect(origin: origin, size: size), display: true)
        orderFront(nil)
    }

    func hide() {
        orderOut(nil)
    }
}

private final class CandidateRow: NSView {
    init(label: String, text: String, isHighlighted: Bool, isHint: Bool = false) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = isHighlighted ? NSColor.selectedContentBackgroundColor.cgColor : nil

        let numberLabel = NSTextField(labelWithString: label)
        numberLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        numberLabel.textColor = isHighlighted ? NSColor.white.withAlphaComponent(0.8) : .secondaryLabelColor

        let textLabel = NSTextField(labelWithString: text)
        textLabel.font = .systemFont(ofSize: 18)
        textLabel.textColor = isHighlighted ? .white : isHint ? .secondaryLabelColor : .labelColor

        let row = NSStackView(views: [numberLabel, textLabel])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
