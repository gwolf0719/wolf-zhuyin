/// 組字狀態機：輸入法外殼把按鍵事件轉成 `Key` 丟進來，照回傳結果更新畫面。
/// 與 InputMethodKit 無關，所以可以直接用測試驗證打字行為。
public struct Composer: Sendable {
    public enum Key: Sendable, Equatable {
        /// 可印出的 ASCII 字元（含空白）。
        case character(Character)
        case enter
        case backspace
        case escape
        case up, down, left, right
        /// 其他按鍵（Tab、快捷鍵）。
        case other
    }

    public struct Result: Sendable, Equatable {
        /// 輸入法是否吃掉這個按鍵；false 表示要交還給 app。
        public var handled: Bool
        /// 這一鍵要送出的文字。
        public var commit: String?
        /// 送出之後組字區應顯示的內容（空字串表示沒有在組字）。
        public var marked: String
        /// 選字窗目前這一頁的內容；空陣列表示不顯示選字窗。
        public var candidates: [String]
        /// 選字窗反白的是這一頁的第幾個。
        public var highlighted: Int

        public init(handled: Bool, commit: String? = nil, marked: String = "", candidates: [String] = [], highlighted: Int = 0) {
            self.handled = handled
            self.commit = commit
            self.marked = marked
            self.candidates = candidates
            self.highlighted = highlighted
        }
    }

    /// 選字窗的狀態。候選字與符號表共用。
    private struct Panel: Sendable {
        var items: [Item]
        var highlighted = 0
        var isSymbols: Bool
    }

    private struct Item: Sendable {
        let text: String
        /// 取代組字內容中從這個按鍵位置到結尾的部分；符號是接在全部內容後面。
        let start: Int
        /// 候選字的讀音；符號沒有。
        var reading: String? = nil
    }

    public static let pageSize = 9
    /// 呼叫符號表的鍵；連按兩下輸出這個字元本身。
    public static let symbolKey: Character = "\\"

    /// 符號表：第一頁是最常用的。
    static let chineseSymbols = [
        "，", "。", "、", "？", "！", "：", "；", "「", "」",
        "（", "）", "『", "』", "《", "》", "…", "—", "～",
        "〈", "〉", "【", "】", "·", "％", "＋", "＝", "＠",
    ]
    static let englishSymbols = [
        ",", ".", "?", "!", ":", ";", "\"", "'", "-",
        "(", ")", "[", "]", "{", "}", "<", ">", "/",
        "_", "|", "@", "#", "$", "%", "&", "*", "~",
    ]

    private let segmenter: Segmenter
    private var keys = ""
    /// 上一次送出的文字是否以中文結尾；決定下一段開頭的標點用全形還是半形。
    private var afterChinese = true
    private var panel: Panel?

    public init(segmenter: Segmenter) {
        self.segmenter = segmenter
    }

    private func text(of keys: String, showPending: Bool = false) -> String {
        segmenter.segment(keys, afterChinese: afterChinese, showPending: showPending).map(\.text).joined()
    }

    /// 目前畫面該有的樣子。
    private func state(handled: Bool = true, commit: String? = nil) -> Result {
        var result = Result(handled: handled, commit: commit, marked: text(of: keys, showPending: true))
        if let panel {
            let pageStart = panel.highlighted / Self.pageSize * Self.pageSize
            result.candidates = panel.items[pageStart..<min(pageStart + Self.pageSize, panel.items.count)].map(\.text)
            result.highlighted = panel.highlighted - pageStart
        }
        return result
    }

    /// 送出一段文字並清空組字狀態。
    private mutating func commit(_ text: String, handled: Bool = true) -> Result {
        keys = ""
        panel = nil
        if let last = text.last { afterChinese = !last.isASCII }
        return Result(handled: handled, commit: text)
    }

    /// 把組字中的內容全部送出（焦點離開、切換輸入法時用）。
    public mutating func flush() -> String? {
        guard !keys.isEmpty else {
            panel = nil
            return nil
        }
        return commit(text(of: keys)).commit
    }

    public mutating func handle(_ key: Key) -> Result {
        if panel != nil, let result = handleInPanel(key) { return result }

        switch key {
        case .character(Self.symbolKey):
            let committedSoFar = text(of: keys)
            let chinese = committedSoFar.last.map { !$0.isASCII } ?? afterChinese
            let symbols = chinese ? Self.chineseSymbols : Self.englishSymbols
            panel = Panel(items: symbols.map { Item(text: $0, start: keys.count) }, isSymbols: true)
            return state()
        case .character(let character):
            // 沒在組字時，空白就是空白。
            if keys.isEmpty, character == " " { return Result(handled: false) }
            keys.append(character)
            return state()
        case .enter:
            guard !keys.isEmpty else { return Result(handled: false) }
            return commit(text(of: keys))
        case .backspace:
            guard !keys.isEmpty else { return Result(handled: false) }
            keys.removeLast()
            return state()
        case .escape:
            guard !keys.isEmpty else { return Result(handled: false) }
            keys = ""
            return state()
        case .down:
            guard !keys.isEmpty else { return Result(handled: false) }
            let candidates = segmenter.candidates(keys, afterChinese: afterChinese)
            if !candidates.isEmpty {
                panel = Panel(items: candidates.map { Item(text: $0.text, start: $0.start, reading: $0.reading) }, isSymbols: false)
            }
            return state()
        case .up, .left, .right:
            // 組字中先不支援移動游標，吃掉按鍵以免游標跑出組字區。
            return keys.isEmpty ? Result(handled: false) : state()
        case .other:
            // 先送出組字內容，再把按鍵交還給 app。
            guard let text = flush() else { return Result(handled: false) }
            return Result(handled: false, commit: text)
        }
    }

    /// 記住使用者的選擇。只改一個字、而且前面緊接著中文字時，連同前一個字記成兩字詞，
    /// 這樣「我再」不會連帶把「他在」也改掉。
    private func learn(_ item: Item, after prefix: String) {
        guard let reading = item.reading, let userPhrases = segmenter.userPhrases else { return }
        if !reading.contains("-"),
           let previous = segmenter.lastChineseSyllable(of: prefix, afterChinese: afterChinese) {
            userPhrases.learn(reading: previous.reading + "-" + reading, text: String(previous.character) + item.text)
        } else {
            userPhrases.learn(reading: reading, text: item.text)
        }
    }

    /// 選字窗開著時的按鍵處理。回傳 nil 表示關掉選字窗後照一般按鍵處理。
    private mutating func handleInPanel(_ key: Key) -> Result? {
        guard var current = panel else { return nil }
        let pageStart = current.highlighted / Self.pageSize * Self.pageSize

        func select(_ index: Int) -> Item? {
            current.items.indices.contains(index) ? current.items[index] : nil
        }
        var chosen: Item?
        switch key {
        case .character(Self.symbolKey) where current.isSymbols:
            // 連按兩下：輸出這個字元本身。
            panel = nil
            keys.append(Self.symbolKey)
            return state()
        case .character(let character) where ("1"..."9").contains(character):
            guard let item = select(pageStart + character.wholeNumberValue! - 1) else { return state() }
            chosen = item
        case .enter, .character(" "):
            chosen = select(current.highlighted)
        case .down:
            current.highlighted = min(current.highlighted + 1, current.items.count - 1)
        case .up:
            current.highlighted = max(current.highlighted - 1, 0)
        case .right:
            if pageStart + Self.pageSize < current.items.count { current.highlighted = pageStart + Self.pageSize }
        case .left:
            current.highlighted = max(pageStart - Self.pageSize, 0)
        case .escape, .backspace:
            panel = nil
            return state()
        case .character, .other:
            panel = nil
            return nil
        }

        if let chosen {
            let prefix = String(keys.prefix(chosen.start))
            learn(chosen, after: prefix)
            return commit(text(of: prefix) + chosen.text)
        }
        panel = current
        return state()
    }
}
