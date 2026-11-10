import Cocoa
import WolfEngine

/// 輸入法平常不顯示視窗；共用同一個實例，避免從選單重複開出設定。
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()

    var terminatesOnClose = false
    private let window: NSWindow
    private var options: [(button: NSButton, keyPath: WritableKeyPath<Preferences, Bool>)] = []
    private let updateButton = NSButton(title: "立即檢查更新", target: nil, action: nil)
    private let updateResult = NSTextField(wrappingLabelWithString: "")

    private override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 430),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        super.init()
        window.title = "狼注音設定"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
        ])

        let descriptions: [(String, String, WritableKeyPath<Preferences, Bool>)] = [
            ("中英文之間自動加空白", "例如「我用 Mac 打字」。", \.autoSpace),
            ("自動修正注音打錯", "聲調按太早、按鍵順序顛倒、按到隔壁鍵。", \.typoTolerance),
            ("記住我的用字習慣", "選過的字、常打的詞、常犯的錯，只存在這台電腦。", \.learning),
            ("打字時預測接下來的字詞", "按 Tab 列出預測，數字鍵選取。", \.predictions),
            ("自動更新", "每天檢查一次，下載後驗證簽章才安裝。", \.autoUpdate),
        ]
        for (title, description, keyPath) in descriptions {
            let checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(optionChanged(_:)))
            checkbox.tag = options.count
            options.append((checkbox, keyPath))
            let detail = NSTextField(labelWithString: description)
            detail.font = .systemFont(ofSize: 11)
            detail.textColor = .secondaryLabelColor
            let row = NSStackView(views: [checkbox, detail])
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 4
            stack.addArrangedSubview(row)
        }

        let separator = NSBox()
        separator.boxType = .separator
        stack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let version = NSTextField(labelWithString: "版本 \(Updater.currentVersion)")
        version.font = .systemFont(ofSize: 11)
        version.textColor = .secondaryLabelColor
        stack.addArrangedSubview(version)

        updateButton.bezelStyle = .rounded
        updateButton.target = self
        updateButton.action = #selector(checkForUpdates(_:))
        updateButton.setContentHuggingPriority(.required, for: .horizontal)
        updateButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        updateResult.font = .systemFont(ofSize: 11)
        updateResult.textColor = .secondaryLabelColor
        updateResult.maximumNumberOfLines = 3
        updateResult.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let updateRow = NSStackView(views: [updateButton, updateResult])
        updateRow.orientation = .horizontal
        updateRow.alignment = .centerY
        updateRow.spacing = 12
        stack.addArrangedSubview(updateRow)
        NSLayoutConstraint.activate([
            updateRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            updateRow.heightAnchor.constraint(equalToConstant: 48),
        ])
        // 視窗高度貼合內容，不留大片空白。
        stack.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 580, height: stack.fittingSize.height + 48))
        window.center()
    }

    func show(checkForUpdates: Bool = false) {
        let preferences = Preferences(defaults: .standard)
        for option in options {
            option.button.state = preferences[keyPath: option.keyPath] ? .on : .off
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if checkForUpdates { self.checkForUpdates(nil) }
    }

    @objc private func optionChanged(_ sender: NSButton) {
        var preferences = Preferences(defaults: .standard)
        preferences[keyPath: options[sender.tag].keyPath] = sender.state == .on
        preferences.save(to: .standard)
        NotificationCenter.default.post(name: Preferences.didChangeNotification, object: nil)
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        guard updateButton.isEnabled else { return }
        updateButton.isEnabled = false
        updateButton.title = "檢查中…"
        updateResult.stringValue = ""
        DispatchQueue.global(qos: .utility).async {
            let result = Updater.checkAndInstall()
            DispatchQueue.main.async {
                self.updateResult.stringValue = result
                self.updateButton.title = "立即檢查更新"
                self.updateButton.isEnabled = true
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        if terminatesOnClose { NSApp.terminate(nil) }
    }
}
