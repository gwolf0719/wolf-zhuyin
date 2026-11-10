/// 組字狀態機：輸入法外殼把按鍵事件轉成 `Key` 丟進來，照回傳結果更新畫面。
/// 與 InputMethodKit 無關，所以可以直接用測試驗證打字行為。
///
/// 緩衝 `keys` 裡有兩種字元：ASCII 是使用者按的鍵，每次都重新轉換；
/// 非 ASCII 是已經定案的文字（從選字窗或符號表選的），原樣輸出、不再變動。
public struct Composer: Sendable {
    public enum Key: Sendable, Equatable {
        /// 可印出的 ASCII 字元（含空白）。
        case character(Character)
        case enter
        case backspace
        case escape
        case up, down, left, right
        case tab
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
        /// 游標在組字區的第幾個字元後面。
        public var cursor: Int
        /// 游標正對著的那個字（游標前面那一個單位）在組字區的範圍；按 ↓ 或退格會動到的就是它。
        /// 游標在最前面時是空範圍。
        public var focus: Range<Int>
        /// 選字窗目前這一頁的內容；空陣列表示不顯示選字窗。
        public var candidates: [String]
        /// 選字窗反白的是這一頁的第幾個。
        public var highlighted: Int
        /// 最可能的後續內容，當作提示顯示；按 Tab 會列出所有預測，再用數字鍵或 Tab 選。nil 表示沒有預測。
        public var prediction: String?

        public init(
            handled: Bool, commit: String? = nil, marked: String = "", cursor: Int? = nil,
            candidates: [String] = [], highlighted: Int = 0, prediction: String? = nil
        ) {
            self.handled = handled
            self.commit = commit
            self.marked = marked
            self.cursor = cursor ?? marked.count
            self.focus = max(self.cursor - 1, 0)..<self.cursor
            self.candidates = candidates
            self.highlighted = highlighted
            self.prediction = prediction
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
        /// 取代緩衝中從這個位置到游標的部分。
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
    private var keys: [Character] = []
    /// 游標在 `keys` 的哪個位置（0...keys.count）。
    private var cursor = 0
    /// 上一次送出的文字是否以中文結尾；決定下一段開頭的標點用全形還是半形。
    private var afterChinese = true
    private var panel: Panel?

    public init(segmenter: Segmenter) {
        self.segmenter = segmenter
    }

    private func text(of keys: some Sequence<Character>) -> String {
        segmenter.segment(String(keys), afterChinese: afterChinese).map(\.text).joined()
    }

    private var beforeCursor: String { String(keys[..<cursor]) }

    /// 目前畫面該有的樣子。
    private func state(handled: Bool = true) -> Result {
        let layout = segmenter.layout(String(keys), afterChinese: afterChinese)
        var result = Result(
            handled: handled, marked: layout.text,
            cursor: layout.stops.last { $0.key <= cursor }?.offset ?? 0
        )
        result.focus = (layout.stops.last { $0.key < cursor }?.offset ?? 0)..<result.cursor
        if let panel {
            let pageStart = panel.highlighted / Self.pageSize * Self.pageSize
            result.candidates = panel.items[pageStart..<min(pageStart + Self.pageSize, panel.items.count)].map(\.text)
            result.highlighted = panel.highlighted - pageStart
        } else {
            result.prediction = currentPredictions.first
        }
        return result
    }

    /// 游標在結尾、選字窗沒開時才預測。
    private var currentPredictions: [String] {
        guard panel == nil, !keys.isEmpty, cursor == keys.count else { return [] }
        return segmenter.predictions(String(keys), afterChinese: afterChinese)
    }

    /// 句末標點（。？！）一出現就把到那裡為止的內容送出，後面的留在組字區。
    /// `.` 也是韻母ㄡ，所以要等它後面又打了一個鍵、仍然被當成句號時才算數；`?` `!` `>` 沒有歧義，立刻送出。
    private mutating func autoCommit() -> Result {
        guard panel == nil, cursor == keys.count else { return state() }
        let layout = segmenter.layout(String(keys), afterChinese: afterChinese)
        let characters = Array(layout.text)
        var commitStop: (key: Int, offset: Int)?
        for stop in layout.stops where stop.offset > 0 && "。？！".contains(characters[stop.offset - 1]) {
            let key = keys[stop.key - 1]
            let isAmbiguous = key == "."
            if !isAmbiguous || stop.key < keys.count { commitStop = stop }
        }
        guard let commitStop else { return state() }
        let committed = String(characters[..<commitStop.offset])
        record(String(keys[..<commitStop.key]))
        keys.removeFirst(commitStop.key)
        cursor = keys.count
        afterChinese = true
        var result = state()
        result.commit = committed
        return result
    }

    /// 把送出的內容記進用詞紀錄。
    private func record(_ committedKeys: String) {
        guard let history = segmenter.history else { return }
        for sentence in segmenter.sentences(committedKeys, afterChinese: afterChinese) { history.record(sentence) }
    }

    /// 把游標移到相鄰的可停位置（不停在一個字的按鍵中間）。
    private mutating func move(_ direction: Key) {
        let stops = segmenter.layout(String(keys), afterChinese: afterChinese).stops.map(\.key)
        switch direction {
        case .left: cursor = stops.last { $0 < cursor } ?? 0
        case .right: cursor = stops.first { $0 > cursor } ?? keys.count
        default: break
        }
    }

    /// 送出一段文字並清空組字狀態。
    private mutating func commit(_ text: String, handled: Bool = true) -> Result {
        record(String(keys))
        keys = []
        cursor = 0
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
            let chinese = text(of: keys[..<cursor]).last.map { !$0.isASCII } ?? afterChinese
            let symbols = chinese ? Self.chineseSymbols : Self.englishSymbols
            panel = Panel(items: symbols.map { Item(text: $0, start: cursor) }, isSymbols: true)
            return state()
        case .character(let character):
            // 沒在組字時，空白就是空白。
            if keys.isEmpty, character == " " { return Result(handled: false) }
            keys.insert(character, at: cursor)
            cursor += 1
            return autoCommit()
        case .tab:
            // 有預測就列出來（再按一次 Tab 選第一個，或按數字鍵選）；沒有就當一般按鍵，送出後交還給 app。
            let predictions = currentPredictions
            guard !predictions.isEmpty else { fallthrough }
            panel = Panel(items: predictions.map { Item(text: $0, start: cursor) }, isSymbols: false)
            return state()
        case .other:
            // 先送出組字內容，再把按鍵交還給 app。
            guard let text = flush() else { return Result(handled: false) }
            return Result(handled: false, commit: text)
        case .enter:
            guard !keys.isEmpty else { return Result(handled: false) }
            return commit(text(of: keys))
        case .backspace:
            guard !keys.isEmpty else { return Result(handled: false) }
            let length = min(cursor, max(1, segmenter.backspaceLength(beforeCursor, afterChinese: afterChinese)))
            keys.removeSubrange(cursor - length..<cursor)
            cursor -= length
            return state()
        case .escape:
            guard !keys.isEmpty else { return Result(handled: false) }
            keys = []
            cursor = 0
            return state()
        case .down:
            guard !keys.isEmpty else { return Result(handled: false) }
            let candidates = segmenter.candidates(beforeCursor, afterChinese: afterChinese)
            if !candidates.isEmpty {
                panel = Panel(items: candidates.map { Item(text: $0.text, start: $0.start, reading: $0.reading) }, isSymbols: false)
            }
            return state()
        case .left, .right:
            guard !keys.isEmpty else { return Result(handled: false) }
            move(key)
            return state()
        case .up:
            // 組字中吃掉，以免游標跑出組字區。
            return keys.isEmpty ? Result(handled: false) : state()
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

        var chosen: Item?
        switch key {
        case .character(Self.symbolKey) where current.isSymbols:
            // 連按兩下：輸出這個字元本身。
            chosen = Item(text: String(Self.symbolKey), start: cursor)
        case .character(let character) where ("1"..."9").contains(character):
            let index = pageStart + character.wholeNumberValue! - 1
            guard current.items.indices.contains(index) else { return state() }
            chosen = current.items[index]
        case .enter, .character(" "), .tab:
            chosen = current.items[current.highlighted]
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
            // 選定的文字直接寫進緩衝，取代原本那幾個按鍵；之後不再被重新轉換。
            learn(chosen, after: String(keys[..<chosen.start]))
            keys.replaceSubrange(chosen.start..<cursor, with: Array(chosen.text))
            cursor = chosen.start + chosen.text.count
            panel = nil
            return autoCommit()
        }
        panel = current
        return state()
    }
}
