import Carbon
import Cocoa
import InputMethodKit
import WolfEngine

/// 最小外殼：只負責把按鍵事件翻成 `Composer.Key`，再照結果更新組字區。行為邏輯都在 `Composer`。
@objc(WolfInputController)
final class WolfInputController: IMKInputController {
    private var composer = Preferences(defaults: .standard).composer(lexicon: sharedLexicon, stores: sharedStores)
    private static let noReplacement = NSRange(location: NSNotFound, length: NSNotFound)

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesDidChange(_:)), name: Preferences.didChangeNotification, object: nil
        )
        debugLog("controller init")
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: Preferences.didChangeNotification, object: nil)
    }

    override func activateServer(_ sender: Any!) {
        debugLog("activateServer")
        super.activateServer(sender)
        reloadPreferences()
    }

    @objc private func preferencesDidChange(_ notification: Notification) {
        reloadPreferences()
    }

    private func reloadPreferences() {
        // 先把舊引擎的組字送回原輸入處，避免切換選項時丟掉尚未送出的字。
        guard let client = client() else { return }
        commitComposition(client)
        composer = Preferences(defaults: .standard).composer(lexicon: sharedLexicon, stores: sharedStores)
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "狼注音設定…", action: #selector(openSettings(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "檢查更新", action: #selector(checkForUpdates(_:)), keyEquivalent: ""))
        return menu
    }

    @objc private func openSettings(_ sender: Any?) {
        SettingsWindow.shared.show()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        SettingsWindow.shared.show(checkForUpdates: true)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown, let client = sender as? IMKTextInput else {
            debugLog("handle：不是 keyDown 或 client 不支援文字輸入")
            return false
        }

        let result = composer.handle(Self.key(for: event))
        // 只記有沒有處理，不記按了什麼鍵。
        debugLog("handle keyDown handled=\(result.handled) commit=\(result.commit != nil)")
        if let text = result.commit {
            client.insertText(text, replacementRange: Self.noReplacement)
        }
        // 游標位置換算成 UTF-16 長度（系統文字 API 的單位）。
        let cursorLocation = String(result.marked.prefix(result.cursor)).utf16.count
        if result.handled {
            client.setMarkedText(
                Self.markedText(for: result),
                selectionRange: NSRange(location: cursorLocation, length: 0),
                replacementRange: Self.noReplacement
            )
        }
        if result.candidates.isEmpty, let prediction = result.prediction {
            CandidatePanel.shared.show(prediction: prediction, near: Self.cursorRect(in: client, at: cursorLocation))
        } else if result.candidates.isEmpty {
            CandidatePanel.shared.hide()
        } else {
            CandidatePanel.shared.show(
                candidates: result.candidates, highlighted: result.highlighted,
                near: Self.cursorRect(in: client, at: cursorLocation)
            )
        }
        return result.handled
    }

    override func deactivateServer(_ sender: Any!) {
        CandidatePanel.shared.hide()
        super.deactivateServer(sender)
        // 新版已換好、要結束行程換版之前，先等學習紀錄寫完。
        if Updater.pendingRestart { sharedStores.flush() }
        Updater.restartIfPending()
    }

    override func commitComposition(_ sender: Any!) {
        CandidatePanel.shared.hide()
        if let client = sender as? IMKTextInput, let text = composer.flush() {
            client.insertText(text, replacementRange: Self.noReplacement)
        }
    }

    /// 組字區的樣式：整段細底線，游標正對著的那個字用粗底線，一眼看得出現在改的是哪個字。
    private static func markedText(for result: Composer.Result) -> NSAttributedString {
        let text = NSMutableAttributedString(string: result.marked)
        let whole = NSRange(location: 0, length: text.length)
        text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: whole)
        text.addAttribute(.markedClauseSegment, value: 0, range: whole)
        guard !result.focus.isEmpty else { return text }
        let start = String(result.marked.prefix(result.focus.lowerBound)).utf16.count
        let end = String(result.marked.prefix(result.focus.upperBound)).utf16.count
        let focus = NSRange(location: start, length: end - start)
        text.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, range: focus)
        text.addAttribute(.markedClauseSegment, value: 1, range: focus)
        return text
    }

    /// 游標在螢幕上的位置。組字區結尾那個位置很多 app 不回報，所以改問前一個字，再不行就問開頭。
    private static func cursorRect(in client: IMKTextInput, at location: Int) -> NSRect {
        for index in [max(location - 1, 0), 0] {
            var rect = NSRect.zero
            client.attributes(forCharacterIndex: index, lineHeightRectangle: &rect)
            if rect != .zero { return rect }
        }
        return .zero
    }

    private static func key(for event: NSEvent) -> Composer.Key {
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return .other }
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter: return .enter
        case kVK_Delete: return .backspace
        case kVK_Escape: return .escape
        case kVK_Tab: return event.modifierFlags.contains(.shift) ? .other : .tab
        case kVK_UpArrow: return .up
        case kVK_DownArrow: return .down
        case kVK_LeftArrow: return .left
        case kVK_RightArrow: return .right
        default: break
        }
        if let characters = event.characters, characters.count == 1,
           let scalar = characters.unicodeScalars.first, (0x20...0x7E).contains(scalar.value) {
            return .character(Character(scalar))
        }
        return .other
    }
}

/// 建了 ~/Library/Logs/WolfZhuyin.debug 這個空檔才寫紀錄到 WolfZhuyin.log。紀錄不含按鍵內容。
private let debugLogURL: URL? = {
    let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
    guard FileManager.default.fileExists(atPath: logs.appendingPathComponent("WolfZhuyin.debug").path) else { return nil }
    return logs.appendingPathComponent("WolfZhuyin.log")
}()

func debugLog(_ message: String) {
    guard let url = debugLogURL, let data = "\(Date()) \(message)\n".data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: url)
    }
}
