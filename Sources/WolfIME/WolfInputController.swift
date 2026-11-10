import Carbon
import Cocoa
import InputMethodKit
import WolfEngine

/// 最小外殼：只負責把按鍵事件翻成 `Composer.Key`，再照結果更新組字區。行為邏輯都在 `Composer`。
@objc(WolfInputController)
final class WolfInputController: IMKInputController {
    private var composer = Composer(segmenter: sharedSegmenter)
    private static let noReplacement = NSRange(location: NSNotFound, length: NSNotFound)

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        debugLog("controller init")
    }

    override func activateServer(_ sender: Any!) {
        debugLog("activateServer")
        super.activateServer(sender)
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
                result.marked,
                selectionRange: NSRange(location: cursorLocation, length: 0),
                replacementRange: Self.noReplacement
            )
        }
        if result.candidates.isEmpty {
            CandidatePanel.shared.hide()
        } else {
            var cursor = NSRect.zero
            client.attributes(forCharacterIndex: cursorLocation, lineHeightRectangle: &cursor)
            CandidatePanel.shared.show(candidates: result.candidates, highlighted: result.highlighted, near: cursor)
        }
        return result.handled
    }

    override func deactivateServer(_ sender: Any!) {
        CandidatePanel.shared.hide()
        super.deactivateServer(sender)
    }

    override func commitComposition(_ sender: Any!) {
        CandidatePanel.shared.hide()
        if let client = sender as? IMKTextInput, let text = composer.flush() {
            client.insertText(text, replacementRange: Self.noReplacement)
        }
    }

    private static func key(for event: NSEvent) -> Composer.Key {
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return .other }
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter: return .enter
        case kVK_Delete: return .backspace
        case kVK_Escape: return .escape
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
