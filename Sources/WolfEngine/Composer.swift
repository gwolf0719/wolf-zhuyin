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
        /// 選了之後先插入的分隔（接受英文預測時補詞間空白）。
        var separator = ""
        /// 實際寫進緩衝的字元；nil 表示就是 `text`（照打的英文要包成不再轉換的字元）。
        var inserted: String? = nil
    }

    public static let pageSize = 9
    /// 呼叫符號表的鍵；連按兩下輸出這個字元本身。
    public static let symbolKey: Character = "\\"

    /// 符號表：第一頁是最常用的。
    /// 半形的 [] 也放第一頁：中文裡 [ ] 鍵會變成「」，使用者（2026-11-11）常用半形的，要好打。
    static let chineseSymbols = [
        "，", "。", "、", "？", "！", "「", "」", "[", "]",
        "：", "；", "（", "）", "『", "』", "《", "》", "…",
        "—", "～", "〈", "〉", "【", "】", "·", "％", "＋",
        "＝", "＠", "{", "}",
    ]
    static let englishSymbols = [
        ",", ".", "?", "!", ":", ";", "\"", "'", "-",
        "(", ")", "[", "]", "{", "}", "<", ">", "/",
        "_", "|", "@", "#", "$", "%", "&", "*", "~",
    ]

    private let segmenter: Segmenter
    private var keys: [Character] = [] {
        didSet { if notes.count != keys.count { notes = Array(notes.prefix(keys.count)) + Array(repeating: nil, count: max(0, keys.count - notes.count)) } }
    }
    /// 和 `keys` 一一對應：從選字窗選定的中文字記下它的讀音（一個字一個音節），
    /// 之後再按 ↓ 還能用讀音重新選字。其他按鍵是 nil。
    private var notes: [String?] = []
    /// 游標在 `keys` 的哪個位置（0...keys.count）。
    private var cursor = 0
    /// 上一次送出的文字是否以中文結尾；決定下一段開頭的標點用全形還是半形。
    private var afterChinese = true
    private var panel: Panel?
    /// 關掉時不提示也不攔 Tab。
    public var predictionsEnabled = true
    /// 剛退格刪掉的按鍵，以及之後在同一個位置重打的按鍵。用來學使用者的打錯習慣。
    private var fix: (deleted: [Character], retyped: [Character], position: Int)?
    /// 剛送出、組字區已清空時，送出的那段文字；用來預測接下來的內容。按了任何鍵就失效，
    /// 所以只有「送出後馬上按 Tab」會被攔下來，其他時候 Tab 照常交給 app。
    private var committedText: String?
    /// 剛送出的那一段（文字、按鍵、選字讀音、當時的全半形語境）。送出後緊接著按退格，可以整段拉回組字區重改。
    /// 按了任何鍵、點了別處、換了視窗就失效。
    private var lastCommit: (text: String, keys: [Character], notes: [String?], afterChinese: Bool)?
    /// 拉回來的那段按鍵：原封不動再送出時不重複記進用詞紀錄。
    private var reopenedKeys: String?

    public init(segmenter: Segmenter) {
        self.segmenter = segmenter
    }

    private func text(of keys: some Sequence<Character>) -> String {
        segmenter.segment(String(keys), afterChinese: afterChinese).map(\.text).joined()
    }

    private var beforeCursor: String { String(keys[..<cursor]) }

    /// 選定的中文字的讀音（按鍵位置 → 讀音）。
    private var readings: [Int: String] {
        Dictionary(uniqueKeysWithValues: notes.enumerated().compactMap { index, note in note.map { (index, $0) } })
    }

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

    /// 游標在結尾、選字窗沒開時才預測；組字區是空的時候，看剛送出的內容。
    /// 外部來源（本機模型）對同一段前文的預測排最前面，再來是自己的用詞紀錄與詞庫。
    private var currentPredictions: [String] {
        guard predictionsEnabled, panel == nil, cursor == keys.count else { return [] }
        let local = keys.isEmpty
            ? committedText.map { segmenter.predictions(following: $0) } ?? []
            : segmenter.predictions(String(keys), afterChinese: afterChinese)
        guard let external, external.context == predictionContext else { return local }
        var merged = external.predictions
        for prediction in local where !merged.contains(prediction) { merged.append(prediction) }
        return Array(merged.prefix(Self.pageSize))
    }

    /// 外部來源對某段前文的預測。前文一變就不算數。
    private var external: (context: String, predictions: [String])?

    /// 現在可以接預測的話，預測要接在哪段文字後面（組字區的文字，或剛送出的文字）；不能預測時是 nil。
    /// 外殼拿這段文字去問本機模型，再用 `offer` 把結果送回來。
    public var predictionContext: String? {
        guard predictionsEnabled, panel == nil, cursor == keys.count else { return nil }
        if keys.isEmpty { return committedText }
        return segmenter.canPredict(after: String(keys), afterChinese: afterChinese) ? text(of: keys) : nil
    }

    /// 外部來源（本機模型）算好的預測。前文已經變了就不採用，回傳 nil；採用的話回傳更新後的畫面。
    public mutating func offer(predictions: [String], for context: String) -> Result? {
        guard predictionContext == context else { return nil }
        let cleaned = predictions.filter { !$0.isEmpty && $0.count <= Self.maximumExternalPredictionLength }
        guard !cleaned.isEmpty else { return nil }
        external = (context, cleaned)
        return state()
    }

    /// 外部預測太長的不要（輸入法是補幾個字，不是代寫整段）。
    public static let maximumExternalPredictionLength = 12

    /// 剛送出、現在按退格可以拉回來重改的那段文字；沒有就是 nil。
    /// 外殼要先確認游標前面真的還是這段文字，再呼叫 `reopen()` 並把它換成組字區。
    public var reopenableText: String? { keys.isEmpty && panel == nil ? lastCommit?.text : nil }

    /// 把剛送出的那段拉回組字區。回傳的畫面要「取代」文件裡剛送出的文字。
    public mutating func reopen() -> Result? {
        guard keys.isEmpty, let last = lastCommit else { return nil }
        lastCommit = nil
        committedText = nil
        panel = nil
        fix = nil
        afterChinese = last.afterChinese
        keys = last.keys
        notes = last.notes
        cursor = keys.count
        reopenedKeys = String(keys)
        return state()
    }

    /// 游標可能已經不在剛送出的文字後面（點了別處、換了視窗）：不能再拉回來。
    public mutating func forgetCommit() {
        lastCommit = nil
    }

    /// 不再提示送出後的預測（使用者點了別的地方、或停太久沒動作）。
    public mutating func dismissPrediction() {
        committedText = nil
    }

    /// 句末標點（。？！）一出現就把到那裡為止的內容送出，後面的留在組字區。
    /// `.` 也是韻母ㄡ，所以要等它後面又打了一個鍵、仍然被當成句號，而且前面是中文字時才算數；`?` `!` `>` 沒有歧義，立刻送出。
    private mutating func autoCommit() -> Result {
        guard panel == nil, cursor == keys.count else { return state() }
        let layout = segmenter.layout(String(keys), afterChinese: afterChinese)
        let characters = Array(layout.text)
        var commitStop: (key: Int, offset: Int)?
        for stop in layout.stops where stop.offset > 0 && "。？！".contains(characters[stop.offset - 1]) {
            let key = keys[stop.key - 1]
            guard key == "." else {
                commitStop = stop
                continue
            }
            // `.` 前面是英數字時多半是 app.json、v1.2 這類內容：下一鍵打到一半時畫面會暫時顯示成句號，
            // 不能拿來判斷，所以不自動送出，等 Enter。前面是中文字、而且後面又打了一個鍵時才算句號。
            let before = stop.offset >= 2 ? characters[stop.offset - 2] : nil
            let afterChineseCharacter = before.map { !$0.isASCII && $0.isLetter } ?? false
            if afterChineseCharacter, stop.key < keys.count { commitStop = stop }
        }
        guard let commitStop else { return state() }
        let committed = String(characters[..<commitStop.offset])
        record(String(keys[..<commitStop.key]))
        let sent = (text: committed, keys: Array(keys[..<commitStop.key]), notes: Array(notes[..<commitStop.key]), afterChinese: afterChinese)
        notes.removeFirst(commitStop.key)
        keys.removeFirst(commitStop.key)
        cursor = keys.count
        afterChinese = true
        if keys.isEmpty {
            committedText = committed
            lastCommit = sent
        }
        var result = state()
        result.commit = committed
        return result
    }

    /// 退格後重打：重打的內容湊成一個完整音節時，跟剛刪掉的開頭比對。
    /// 很像（順序不同、差一鍵）就記成一次「打錯 → 更正」；刪掉的那段本身若是正確的音節或英文字，不算打錯。
    private mutating func observeRetyped(_ character: Character) {
        guard var current = fix, character.isASCII, cursor == current.position + current.retyped.count + 1 else {
            fix = nil
            return
        }
        current.retyped.append(character)
        fix = current
        guard let syllable = Dachen.syllable(in: current.retyped, from: 0) else {
            if current.retyped.count > 5 { fix = nil }
            return
        }
        guard syllable.end == current.retyped.count, segmenter.lexicon.syllables.contains(syllable.reading) else {
            fix = nil
            return
        }
        // 刪掉的內容可能不只一個字：取開頭長度相近的那一段來比。
        let length = current.retyped.count
        for candidate in [length, length - 1, length + 1] where candidate >= 2 && candidate <= current.deleted.count {
            let mistyped = Array(current.deleted.prefix(candidate))
            if mistyped == current.retyped {
                // 這個字原本就打對了，只是跟著被刪掉；繼續看後面的。
                fix = (Array(current.deleted.dropFirst(candidate)), [], cursor)
                return
            }
            guard UserTypos.looksLikeSameSyllable(mistyped, current.retyped) else { continue }
            let wasValidSyllable = Dachen.syllable(in: mistyped, from: 0).map {
                $0.end == mistyped.count && segmenter.lexicon.syllables.contains($0.reading)
            } ?? false
            if !wasValidSyllable, segmenter.english.tier(of: String(mistyped)) == nil {
                segmenter.typos?.learn(mistyped: String(mistyped), intended: String(current.retyped))
            }
            fix = (Array(current.deleted.dropFirst(candidate)), [], cursor)
            return
        }
        fix = nil
    }

    /// 把送出的內容記進用詞紀錄。
    private mutating func record(_ committedKeys: String) {
        defer { reopenedKeys = nil }
        guard let history = segmenter.history, committedKeys != reopenedKeys else { return }
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
        lastCommit = keys.isEmpty ? nil : (text, keys, notes, afterChinese)
        keys = []
        cursor = 0
        panel = nil
        if let last = text.last { afterChinese = !last.isASCII }
        committedText = text
        var result = Result(handled: handled, commit: text)
        result.prediction = currentPredictions.first
        return result
    }

    /// 把組字中的內容全部送出（焦點離開、切換輸入法時用）。
    public mutating func flush() -> String? {
        guard !keys.isEmpty else {
            panel = nil
            return nil
        }
        let text = commit(text(of: keys)).commit
        committedText = nil
        lastCommit = nil
        return text
    }

    public mutating func handle(_ key: Key) -> Result {
        // 退格之後只有「接著打字」或「繼續退格」才算在更正；其他動作都結束這次觀察。
        switch key {
        case .character, .backspace: break
        default: fix = nil
        }
        // 送出後的預測只留給緊接著的這一鍵。
        let lastCommitted = committedText
        committedText = nil
        lastCommit = nil
        if panel != nil {
            fix = nil
            if let result = handleInPanel(key) { return result }
        }

        switch key {
        case .character(Self.symbolKey):
            let chinese = text(of: keys[..<cursor]).last.map { !$0.isASCII } ?? afterChinese
            let symbols = chinese ? Self.chineseSymbols : Self.englishSymbols
            // 中文符號表裡的半形符號（[]）要照打：不包起來的話，接在中文後面又會被換成「」。
            panel = Panel(items: symbols.map { symbol in
                let asIs = chinese && symbol.allSatisfy(\.isASCII)
                return Item(text: symbol, start: cursor, inserted: asIs ? String(symbol.map(Segmenter.literal)) : nil)
            }, isSymbols: true)
            return state()
        case .character(let character):
            // 沒在組字時，空白就是空白。
            if keys.isEmpty, character == " " { return Result(handled: false) }
            notes.insert(nil, at: cursor)
            keys.insert(character, at: cursor)
            cursor += 1
            observeRetyped(character)
            return autoCommit()
        case .tab:
            // 有預測就列出來（再按一次 Tab 選第一個，或按數字鍵選）；沒有就當一般按鍵，送出後交還給 app。
            committedText = lastCommitted
            let predictions = currentPredictions
            committedText = nil
            guard !predictions.isEmpty else { fallthrough }
            // 英文接英文要有空白（hello + world），中文不用。
            func isLatin(_ character: Character?) -> Bool {
                character.map { $0.isASCII && ($0.isLetter || $0.isNumber) } ?? false
            }
            let previous = keys.last ?? lastCommitted?.last
            panel = Panel(items: predictions.map { prediction in
                Item(text: prediction, start: cursor, separator: isLatin(previous) && isLatin(prediction.first) ? " " : "")
            }, isSymbols: false)
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
            // 游標在結尾：照畫面單位刪（打到一半的音節一次一個符號、打錯的亂碼整串）。
            // 游標在中間：刪掉游標前面那個字，邊界取自整段的轉換結果。
            let length = cursor == keys.count
                ? min(cursor, max(1, segmenter.backspaceLength(beforeCursor, afterChinese: afterChinese)))
                : cursor - segmenter.unitStart(String(keys), before: cursor, afterChinese: afterChinese)
            let removed = Array(keys[cursor - length..<cursor])
            notes.removeSubrange(cursor - length..<cursor)
            keys.removeSubrange(cursor - length..<cursor)
            cursor -= length
            if !removed.allSatisfy(\.isASCII) {
                fix = nil
            } else if let current = fix, current.retyped.isEmpty, current.position == cursor + length {
                // 連續退格：刪掉的內容接在前面。
                fix = (removed + current.deleted, [], cursor)
            } else {
                fix = (removed, [], cursor)
            }
            return state()
        case .escape:
            guard !keys.isEmpty else { return Result(handled: false) }
            keys = []
            cursor = 0
            return state()
        case .down:
            guard !keys.isEmpty else { return Result(handled: false) }
            let candidates = segmenter.candidates(String(keys), cursor: cursor, afterChinese: afterChinese, readings: readings)
            if !candidates.isEmpty {
                panel = Panel(items: candidates.map {
                    Item(text: $0.text, start: $0.start, reading: $0.reading, inserted: $0.inserted)
                }, isSymbols: false)
            }
            return state()
        case .left, .right:
            guard !keys.isEmpty else { return Result(handled: false) }
            move(key)
            return state()
        case .up:
            guard !keys.isEmpty else { return Result(handled: false) }
            // 跳到游標左邊最近一個「輸入法沒把握」的字並開選字窗；左邊沒有了就從結尾繞回來。
            // 不必用方向鍵一格一格移過去。沒有可疑的字時只吃掉按鍵，以免游標跑出組字區。
            let doubtful = segmenter.doubtfulStops(String(keys), afterChinese: afterChinese, fixed: Set(readings.keys))
            guard let target = doubtful.last(where: { $0 < cursor }) ?? doubtful.last else { return state() }
            cursor = target
            return handle(.down)
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
            let inserted = Array(chosen.separator + (chosen.inserted ?? chosen.text))
            // 從選字窗選了「可能是打錯」的候選：記成一次更正，累積成打錯習慣。
            let original = Array(keys[chosen.start..<cursor])
            if let reading = chosen.reading, !reading.contains("-"), original.allSatisfy(\.isASCII),
               let canonical = Dachen.keys(forReading: reading), UserTypos.kind(original, Array(canonical)) != nil {
                segmenter.typos?.learn(mistyped: String(original), intended: canonical)
            }
            // 中文候選一個字對一個音節時，記下每個字的讀音。
            let syllables = chosen.reading?.split(separator: "-").map(String.init) ?? []
            let newNotes: [String?] = chosen.separator.isEmpty && syllables.count == inserted.count
                ? syllables : Array(repeating: nil, count: inserted.count)
            notes.replaceSubrange(chosen.start..<cursor, with: newNotes)
            keys.replaceSubrange(chosen.start..<cursor, with: inserted)
            cursor = chosen.start + inserted.count
            panel = nil
            return autoCommit()
        }
        panel = current
        return state()
    }
}
