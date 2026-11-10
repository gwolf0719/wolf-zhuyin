import Carbon
import Cocoa
import InputMethodKit
import WolfEngine

/// 最小外殼：只負責把按鍵事件翻成 `Composer.Key`，再照結果更新組字區。行為邏輯都在 `Composer`。
@objc(WolfInputController)
final class WolfInputController: IMKInputController {
    private var composer = Preferences(defaults: .standard).composer(lexicon: sharedLexicon, stores: sharedStores)
    private static let noReplacement = NSRange(location: NSNotFound, length: NSNotFound)
    /// 送出後的預測提示放多久；停太久沒動作就收掉，之後的 Tab 照常交給 app。
    private static let predictionLifetime: TimeInterval = 8
    private var predictionExpiry: DispatchWorkItem?
    private var composerIsIdle = true
    /// 用本機模型補充預測（設定裡的開關，而且模型可用）。
    private var usesModelPredictions = false
    /// 最近送出的文字，給模型當前文。換視窗、點滑鼠就清掉，因為游標可能已經不在原處。
    private var recentCommitted = ""
    private var modelRequest: DispatchWorkItem?
    private var lastCursorRect = NSRect.zero
    /// 停止打字這麼久才問模型，避免每打一鍵就問一次。
    private static let modelDelay: TimeInterval = 0.25

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
        let preferences = Preferences(defaults: .standard)
        composer = preferences.composer(lexicon: sharedLexicon, stores: sharedStores)
        usesModelPredictions = preferences.predictions && preferences.modelPredictions && ModelPredictor.isAvailable
    }

    /// 停頓一下之後，把目前的句子交給本機模型續寫；結果回來時前文沒變才採用。
    private func requestModelPrediction() {
        modelRequest?.cancel()
        modelRequest = nil
        guard usesModelPredictions, let context = composer.predictionContext, !context.isEmpty else { return }
        // 組字中：前文是「最近送出的＋組字區」；剛送出：最近送出的結尾就是它。
        let text = recentCommitted.hasSuffix(context) ? recentCommitted : recentCommitted + context
        let request = DispatchWorkItem { [weak self] in
            ModelPredictor.predict(after: text) { predictions in
                guard let self, let result = self.composer.offer(predictions: predictions, for: context),
                      result.candidates.isEmpty, let prediction = result.prediction else { return }
                CandidatePanel.shared.show(prediction: prediction, near: self.lastCursorRect)
                if result.marked.isEmpty { self.schedulePredictionExpiry() }
            }
        }
        modelRequest = request
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.modelDelay, execute: request)
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "狼注音設定…", action: #selector(openSettings(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "學習紀錄…", action: #selector(openLearned(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "檢查更新", action: #selector(checkForUpdates(_:)), keyEquivalent: ""))
        return menu
    }

    @objc private func openSettings(_ sender: Any?) {
        SettingsWindow.shared.show()
    }

    @objc private func openLearned(_ sender: Any?) {
        // 先把還在組字的內容送出，紀錄才是最新的。
        if let client = client() { commitComposition(client) }
        if LearnedWindow.shared == nil { LearnedWindow.shared = LearnedWindow(stores: sharedStores) }
        LearnedWindow.shared?.show()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        SettingsWindow.shared.show(checkForUpdates: true)
    }

    /// 除了按鍵，也收滑鼠點擊：點了別的地方，送出後的預測就不算數。
    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .leftMouseDown, .rightMouseDown]).rawValue)
    }

    /// 送出後的預測提示放一陣子就收掉，之後的 Tab 照常交給 app。
    private func schedulePredictionExpiry() {
        predictionExpiry?.cancel()
        let expiry = DispatchWorkItem { [weak self] in self?.dismissPrediction() }
        predictionExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.predictionLifetime, execute: expiry)
    }

    private func dismissPrediction() {
        modelRequest?.cancel()
        modelRequest = nil
        predictionExpiry?.cancel()
        predictionExpiry = nil
        composer.dismissPrediction()
        CandidatePanel.shared.hide()
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        if let event, event.type == .leftMouseDown || event.type == .rightMouseDown {
            // 只在沒有組字時收掉預測；組字中的點擊照系統原本的方式處理。
            // 游標可能被點到別處了，之前送出的文字不再是前文。
            recentCommitted = ""
            if composerIsIdle { dismissPrediction() }
            return false
        }
        guard let event, event.type == .keyDown, let client = sender as? IMKTextInput else {
            debugLog("handle：不是 keyDown 或 client 不支援文字輸入")
            return false
        }

        let result = composer.handle(Self.key(for: event))
        // 只記有沒有處理，不記按了什麼鍵。
        debugLog("handle keyDown handled=\(result.handled) commit=\(result.commit != nil)")
        if let text = result.commit {
            client.insertText(text, replacementRange: Self.noReplacement)
            recentCommitted = String((recentCommitted + text).suffix(ModelPredictor.contextLength))
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
        predictionExpiry?.cancel()
        predictionExpiry = nil
        composerIsIdle = result.marked.isEmpty
        if result.candidates.isEmpty, let prediction = result.prediction {
            CandidatePanel.shared.show(prediction: prediction, near: Self.cursorRect(in: client, at: cursorLocation))
            if result.marked.isEmpty { schedulePredictionExpiry() }
        } else if result.candidates.isEmpty {
            CandidatePanel.shared.hide()
        } else {
            CandidatePanel.shared.show(
                candidates: result.candidates, highlighted: result.highlighted,
                near: Self.cursorRect(in: client, at: cursorLocation)
            )
        }
        lastCursorRect = Self.cursorRect(in: client, at: cursorLocation)
        requestModelPrediction()
        return result.handled
    }

    override func deactivateServer(_ sender: Any!) {
        recentCommitted = ""
        dismissPrediction()
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
