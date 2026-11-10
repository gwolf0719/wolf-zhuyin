/// 把一串原始按鍵切成中文段與英文段，並給出各段的輸出文字。
///
/// 做法：按鍵位置之間拉三種邊（中文詞、英文詞、原樣輸出的單一按鍵），
/// 每條邊有 log10 分數，用動態規劃找總分最高的路徑。
public struct Segmenter: Sendable {
    public enum Language: Sendable { case chinese, english }

    public struct Segment: Sendable, Equatable {
        public let language: Language
        public let keys: Range<Int>
        public let text: String
    }

    public struct Weights: Sendable {
        /// 常用英文字。
        public var commonWord = -3.5
        /// 常用表裡夾數字的字（mp4、x86）：字母夾數字幾乎不會是打錯的注音，證據比一般英文字強。
        public var alphanumericWord = -2.0
        /// 只在大詞表裡的英文字。
        public var dictionaryWord = -5.0
        /// 無法解讀、原樣輸出的單一按鍵。
        public var rawKey = -5.0
        /// 原樣輸出的大寫字母：大寫不可能是注音，沒有歧義，所以代價低。
        public var rawUppercase = -1.5
        /// 原樣輸出的空白。
        public var rawSpace = -0.3
        /// 標點。
        public var punctuation = -1.0
        /// 是否修正注音打錯。
        public var typoTolerance = true
        /// 修正「按鍵順序顛倒」的代價。
        public var typoOrder = -1.5
        /// 修正「漏按聲調」的代價。
        public var typoMissingTone = -2.5
        /// 修正「按到隔壁鍵」的代價。
        public var typoNeighbor = -4.0
        /// 修正「使用者自己常犯的錯」的代價。
        public var typoPersonal = -0.5
        /// 修正後組成的詞至少要這麼常見才採用。
        public var typoMinWordScore = -6.0
        /// 中英切換一次的代價。
        public var languageSwitch = -1.0
        /// 每多一個中文詞的代價：讓「再說」這種完整的詞贏過拆開的「在＋說」。
        public var chineseWord = -0.5
        /// 前後字搭配分數的倍數；0 表示不看上下文。
        public var context = 1.0
        /// 同一個讀音最多拿幾個同音詞去比上下文。
        public var homophones = 4
        /// 分數比最常見的同音詞低超過這麼多的，不拿來比上下文。
        public var homophoneMargin = 3.0
        public init() {}
    }

    public let lexicon: Lexicon
    /// 使用者選過的字詞；有設定時，轉換與候選都優先採用。
    public var userPhrases: UserPhrases?
    /// 使用者送出過的詞序；有設定時，預測優先參考它。
    public var history: UserHistory?
    /// 使用者個人的打錯習慣；有設定時，他常犯的錯會直接修正。
    public var typos: UserTypos?
    /// 輸出時在中文與英文、數字之間自動加空白。只影響顯示與送出的文字，不影響分段與學習。
    public var autoSpace = false
    public let english: EnglishWords
    public var weights = Weights()
    /// 同音字依上下文挑選的規則。
    public var context = CharacterContext()

    public init(lexicon: Lexicon, english: EnglishWords = EnglishWords()) {
        self.lexicon = lexicon
        self.english = english
    }

    private struct Edge {
        let start: Int
        let end: Int
        let language: Language
        let text: String
        let score: Double
        /// 中文詞的讀音（如 ㄋㄧˇ-ㄏㄠˇ）。
        var reading: String? = nil
        /// 中文詞每個音節結束的按鍵位置（容錯後音節的按鍵不一定照標準排列，所以要另外記）。
        var syllableEnds: [Int] = []
        /// 這條邊是把打錯的按鍵修正後才成立的。
        var isCorrection = false
        /// 原樣輸出的單一按鍵。
        var isRawKey = false
        /// 標點邊：不改變前面的語言狀態，全形或半形等整條路徑定案後再決定。
        var punctuation: Character? = nil
    }

    /// 某個位置可以解讀成的一個音節。
    private struct SyllableOption {
        let reading: String
        let end: Int
        /// 0 表示照標準打法；負數是修正打錯的代價。
        let penalty: Double
        /// 根據使用者自己更正過的紀錄修的：證據夠強，不必再靠旁邊的字成詞。
        var isPersonal = false
    }

    private static let maxSyllablesPerWord = 8

    /// 有全形版本的標點鍵。
    static let fullWidthPunctuation: [Character: Character] = [
        ",": "，", ".": "。", "?": "？", "!": "！", ":": "：", ";": "；", "'": "、",
        "(": "（", ")": "）", "[": "「", "]": "」", "{": "『", "}": "』", "<": "，", ">": "。", "~": "～",
    ]

    private static let closingBrackets: [Character: Character] = [")": "(", "]": "[", "}": "{"]

    /// 路徑上的一小段：一個中文詞、一個英文字、一個標點或一個原樣輸出的按鍵。
    struct Piece {
        var language: Language
        let keys: Range<Int>
        var text: String
        var reading: String?
        /// 中文詞每個音節結束的按鍵位置。
        var syllableEnds: [Int] = []
        /// 無法解讀、原樣輸出的單一按鍵。
        var isRawKey = false
        /// 結尾打到一半的音節。
        var isPending = false
        /// 自動空白：輸出時在這段後面補一個空白。不算進這段的文字，所以游標位置照字計算。
        var trailingSpace = false
    }

    public struct Candidate: Sendable, Equatable {
        public let text: String
        /// 選了這個候選後，會取代從這個按鍵位置到結尾的內容。
        public let start: Int
        public let reading: String
    }

    /// 使用者最近選的字詞要有多少優勢：比詞庫第一名高這麼多，而且至少有 `learnedFloor` 分，
    /// 讓學到的新詞（詞庫裡沒有的組合）贏過拆成單字的走法。
    private static let learnedBonus = 0.3
    private static let learnedFloor = -3.0

    /// 某個讀音的所有字詞：使用者選過的在前（最近的最優先），其餘照詞庫分數。
    func entries(for reading: String) -> [Lexicon.Entry] {
        let base = lexicon.entries[reading] ?? []
        guard let learned = userPhrases?.texts(for: reading), let latest = learned.first else { return base }
        let top = base.first?.score ?? -.infinity
        var result = [Lexicon.Entry(text: latest, score: max(top + Self.learnedBonus, Self.learnedFloor))]
        result += base.filter { $0.text != latest }
        return result
    }

    /// 這串按鍵轉換後，結尾若是中文字，回傳最後一個音節的讀音與那個字。
    func lastChineseSyllable(of input: String, afterChinese: Bool) -> (reading: String, character: Character)? {
        guard let piece = pieces(Array(input), afterChinese: afterChinese, showPending: false).last,
              let reading = piece.reading?.split(separator: "-").last, let character = piece.text.last else { return nil }
        return (String(reading), character)
    }

    /// - Parameters:
    ///   - afterChinese: 這串按鍵之前的文字是不是中文；整串只有標點時用它決定全形或半形。
    ///   - showPending: 結尾還沒按聲調的音節要不要顯示成注音符號（組字區用 true，送出用 false）。
    public func segment(_ input: String, afterChinese: Bool = true, showPending: Bool = false) -> [Segment] {
        var segments: [Segment] = []
        for piece in spaced(pieces(Array(input), afterChinese: afterChinese, showPending: showPending)) {
            let text = piece.trailingSpace ? piece.text + " " : piece.text
            if let last = segments.last, last.language == piece.language {
                segments[segments.count - 1] = Segment(
                    language: piece.language,
                    keys: last.keys.lowerBound..<piece.keys.upperBound,
                    text: last.text + text
                )
            } else {
                segments.append(Segment(language: piece.language, keys: piece.keys, text: text))
            }
        }
        return segments
    }

    /// 游標前面那幾個中文字的其他選擇：先列較長的詞，再列單字。游標前不是中文時回傳空陣列。
    /// 音節邊界取自整段的轉換結果，而不是只看游標前那一截重新判斷——
    /// 否則游標在中間時，被修正過或靠後文成詞的字會被切錯。
    /// - Parameter cursor: 游標在按鍵中的位置；nil 表示結尾。
    public func candidates(_ input: String, cursor: Int? = nil, afterChinese: Bool = true) -> [Candidate] {
        let keys = Array(input)
        let cursor = cursor ?? keys.count
        // 把整段的中文詞拆回音節，分成一串串連續的中文。
        var runs: [[(reading: String, start: Int, end: Int)]] = [[]]
        for piece in pieces(keys, afterChinese: afterChinese, showPending: false) {
            guard let reading = piece.reading else {
                runs.append([])
                continue
            }
            let starts = [piece.keys.lowerBound] + piece.syllableEnds.dropLast()
            for (syllable, (start, end)) in zip(reading.split(separator: "-"), zip(starts, piece.syllableEnds)) {
                runs[runs.count - 1].append((String(syllable), start, end))
            }
        }
        guard let run = runs.first(where: { $0.contains { $0.end == cursor } }),
              let last = run.firstIndex(where: { $0.end == cursor }) else { return [] }
        let syllables = run[...last].map { (reading: $0.reading, start: $0.start) }
        var result: [Candidate] = []
        var seen: Set<String> = []
        for length in stride(from: min(syllables.count, Self.maxSyllablesPerWord), through: 1, by: -1) {
            let tail = syllables.suffix(length)
            let reading = tail.map(\.reading).joined(separator: "-")
            for entry in entries(for: reading) where seen.insert(entry.text).inserted {
                result.append(Candidate(text: entry.text, start: tail.first!.start, reading: reading))
            }
        }
        return result
    }

    /// 開啟自動空白時，在「中文字 ↔ 英文字母或數字」相鄰的地方，於前一段結尾補一個空白。
    /// 標點、空白旁邊不補；已經有空白的不重複補。
    private func spaced(_ pieces: [Piece]) -> [Piece] {
        guard autoSpace, pieces.count >= 2 else { return pieces }
        func isHan(_ character: Character?) -> Bool {
            character.map { !$0.isASCII && $0.isLetter } ?? false
        }
        func isLatin(_ character: Character?) -> Bool {
            character.map { $0.isASCII && ($0.isLetter || $0.isNumber) } ?? false
        }
        var result = pieces
        for index in result.indices.dropLast() {
            let before = result[index].text.last
            let after = result[index + 1].text.first
            if (isHan(before) && isLatin(after)) || (isLatin(before) && isHan(after)) {
                result[index].trailingSpace = true
            }
        }
        return result
    }

    /// 把轉換結果拆成一個個詞（給用詞紀錄用）：中文詞、英文字各算一個；標點與空白把句子切開。
    public func sentences(_ input: String, afterChinese: Bool = true) -> [[String]] {
        var result: [[String]] = [[]]
        var literal = ""
        func flushLiteral() {
            if !literal.isEmpty { result[result.count - 1].append(literal) }
            literal = ""
        }
        let keys = Array(input)
        for piece in pieces(keys, afterChinese: afterChinese, showPending: false) {
            let isLiteral = piece.keys.count == 1 && !keys[piece.keys.lowerBound].isASCII
            let isWord = piece.reading != nil || (piece.language == .english && !piece.isRawKey && piece.text.allSatisfy(\.isLetter))
            if isLiteral, piece.text.allSatisfy({ $0.isLetter }) {
                // 從選字窗或預測選進來的字是一個一個存的，相連的併成一個詞。
                literal += piece.text
            } else if isWord {
                flushLiteral()
                result[result.count - 1].append(piece.text)
            } else {
                flushLiteral()
                if piece.text != " " { result.append([]) }
            }
        }
        flushLiteral()
        return result.filter { !$0.isEmpty }
    }

    /// 預測接下來的內容，最可能的在前，最多 9 個。結尾必須是完整的詞（不是打到一半的音節、標點或空白）。
    /// 使用者自己的用詞紀錄排前面；結尾是中文時再補上詞庫裡以它開頭的常見詞。
    public func predictions(_ input: String, afterChinese: Bool = true) -> [String] {
        let keys = Array(input)
        let all = pieces(keys, afterChinese: afterChinese, showPending: true)
        guard let last = all.last, !last.isPending, !last.isRawKey, last.text != " ",
              let words = sentences(input, afterChinese: afterChinese).last, let lastWord = words.last,
              last.text.last == lastWord.last else { return [] }
        return predictions(afterWords: words)
    }

    /// 送出之後、組字區是空的時候預測接下來的內容：剛送出的結尾是句末標點就預測下一句的開頭，
    /// 是中文字或英文字就預測它的後續；其他情況（逗號、空白、數字…）不預測。
    public func predictions(following committed: String) -> [String] {
        guard let last = committed.last else { return [] }
        if "。？！?!".contains(last) {
            return Array((history?.likely(after: [UserHistory.sentenceStart]) ?? []).prefix(9))
        }
        let words: [String]
        if last.isASCII {
            let word = String(committed.reversed().prefix { $0.isASCII && $0.isLetter }.reversed())
            words = word.isEmpty ? [] : [word]
        } else {
            words = committed.reversed().prefix { !$0.isASCII && $0.isLetter }.reversed().map(String.init)
        }
        return words.isEmpty ? [] : predictions(afterWords: words)
    }

    /// 前文（照順序的詞）之後最可能接什麼。
    private func predictions(afterWords words: [String]) -> [String] {
        var result = history?.likely(after: words) ?? []

        // 結尾連續的中文字：較長的前文比較準，排前面。
        var tail = ""
        for word in words.reversed() {
            guard !word.allSatisfy(\.isASCII) else { break }
            tail = word + tail
        }
        for length in stride(from: min(tail.count, 6), through: 2, by: -1) {
            for rest in lexicon.continuations[String(tail.suffix(length))] ?? [] where !result.contains(rest) {
                result.append(rest)
            }
        }
        return Array(result.prefix(9))
    }

    /// 組字區要顯示的文字，以及游標可以停的位置（按鍵位置 ↔ 文字位置）。
    /// 中文一個字停一次、英文一個字母停一次，不會停在一個字的按鍵中間。
    public func layout(_ input: String, afterChinese: Bool = true) -> (text: String, stops: [(key: Int, offset: Int)]) {
        let keys = Array(input)
        var text = ""
        var stops = [(key: 0, offset: 0)]
        for piece in spaced(pieces(keys, afterChinese: afterChinese, showPending: true)) {
            let base = text.count
            text += piece.text
            if piece.reading != nil, piece.syllableEnds.count == piece.text.count {
                for (index, end) in piece.syllableEnds.enumerated() { stops.append((end, base + index + 1)) }
            } else if piece.language == .english, piece.keys.count == piece.text.count {
                for index in 1...piece.text.count { stops.append((piece.keys.lowerBound + index, base + index)) }
            }
            if stops.last?.key != piece.keys.upperBound { stops.append((piece.keys.upperBound, text.count)) }
            // 補上的空白不是可以停的位置。
            if piece.trailingSpace { text += " " }
        }
        return (text, stops)
    }

    /// 游標前面那個單位（一個中文字、一個英文字母…）從哪個按鍵開始。用整段的版面判斷，給中間編輯用。
    public func unitStart(_ input: String, before cursor: Int, afterChinese: Bool = true) -> Int {
        layout(input, afterChinese: afterChinese).stops.last { $0.key < cursor }?.key ?? 0
    }

    /// 按一次退格該刪掉結尾幾個按鍵。以「畫面上的一個單位」為準：
    /// - 打到一半的音節：一個注音符號。
    /// - 已完成的中文字：整個字（含聲調）。
    /// - 沒被認出來的一串按鍵（多半是注音打錯）：整串。判斷依據是裡面有數字或注音用到的符號鍵；
    ///   純字母的不算，那可能是詞表沒收的英文字，照一般習慣一次刪一個字母。
    /// - 其他（英文字、標點、空白）：一個字元。
    public func backspaceLength(_ input: String, afterChinese: Bool = true) -> Int {
        let keys = Array(input)
        let all = pieces(keys, afterChinese: afterChinese, showPending: true)
        guard let last = all.last else { return 0 }
        if last.isPending { return 1 }
        if last.reading != nil {
            let lastSyllableStart = last.syllableEnds.dropLast().last ?? last.keys.lowerBound
            return keys.count - lastSyllableStart
        }
        guard last.isRawKey, keys[last.keys.lowerBound] != " " else { return 1 }
        let run = all.reversed().prefix { $0.isRawKey && keys[$0.keys.lowerBound] != " " }
        let looksLikeMistypedZhuyin = run.contains { !keys[$0.keys.lowerBound].isLetter }
        return looksLikeMistypedZhuyin ? run.count : 1
    }

    func pieces(_ keys: [Character], afterChinese: Bool, showPending: Bool) -> [Piece] {
        guard !keys.isEmpty else { return [] }
        if showPending, let pending = pendingSyllable(in: keys) {
            // 結尾是打到一半的音節：前面的部分單獨轉換（不讓還沒打完的按鍵影響前面的判斷），結尾顯示注音符號。
            var result = resolve(pending.head, afterChinese: afterChinese)
            result.append(Piece(language: .chinese, keys: pending.start..<keys.count, text: pending.symbols, isPending: true))
            return result
        }
        return resolve(bestPath(keys), afterChinese: afterChinese)
    }

    /// 整串按鍵分數最高的解讀。
    private func bestPath(_ keys: [Character]) -> [Edge] {
        guard !keys.isEmpty else { return [] }
        // 狀態＝（最後一條邊的語言, 最後一個字）。記最後一個字是為了算前後字搭配：
        // 「明天」後面接「再」或「在」，分數不同。每個位置只有幾條邊結束，狀態數量很小。
        struct State: Hashable {
            let language: Language
            let last: Character
        }
        typealias Entry = (score: Double, edge: Edge?, previous: State?)
        let context = self.context
        let contextWeight = weights.context
        func contextScore(_ previous: Character, _ next: Character) -> Double {
            contextWeight == 0 ? 0 : contextWeight * context.score(previous, next)
        }
        /// 走過這條邊之後，下一個字看到的「前一個字」。
        func lastCharacter(after edge: Edge) -> Character {
            if edge.punctuation != nil { return CharacterContext.sentenceStart }
            guard let last = edge.text.last else { return CharacterContext.sentenceStart }
            if edge.language == .chinese { return last }
            if last.isNumber { return CharacterContext.afterNumber }
            if last.isLetter { return CharacterContext.afterLatin }
            return CharacterContext.sentenceStart
        }
        var best = Array(repeating: [State: Entry](), count: keys.count + 1)
        for language in [Language.chinese, .english] {
            best[0][State(language: language, last: CharacterContext.sentenceStart)] = (0, nil, nil)
        }

        for position in 0..<keys.count where !best[position].isEmpty {
            for edge in edges(in: keys, from: position) {
                for (state, entry) in best[position] {
                    // 修正打錯的邊只能出現在中文語境：開頭、中文後面，或空白與標點後面。
                    // 緊接在英數字後面的不修，避免把英文字的後半段改成中文。
                    if edge.isCorrection, position > 0, state.language == .english,
                       keys[position - 1].isLetter || keys[position - 1].isNumber { continue }
                    // 標點邊維持前一個語言狀態，不算切換。
                    if edge.punctuation != nil, state.language != edge.language { continue }
                    let switched = position > 0 && state.language != edge.language
                    var score = entry.score + edge.score + (switched ? weights.languageSwitch : 0)
                    if edge.language == .chinese, edge.punctuation == nil, let first = edge.text.first {
                        score += contextScore(state.last, first)
                    } else if edge.punctuation != nil, state.language == .chinese {
                        score += contextScore(state.last, CharacterContext.sentenceEnd)
                    }
                    let next = State(language: edge.language, last: lastCharacter(after: edge))
                    if score > best[edge.end][next]?.score ?? -.infinity {
                        best[edge.end][next] = (score, edge, state)
                    }
                }
            }
        }

        // 結尾：中文字收尾時也算一次「句子結束」的搭配（他不「在」比他不「再」常收尾）。
        func finalScore(_ state: State, _ entry: Entry) -> Double {
            entry.score + (state.language == .chinese ? contextScore(state.last, CharacterContext.sentenceEnd) : 0)
        }
        var path: [Edge] = []
        var position = keys.count
        var state = best[position].max { finalScore($0.key, $0.value) < finalScore($1.key, $1.value) }?.key
        while position > 0, let current = state, let step = best[position][current], let edge = step.edge {
            path.append(edge)
            position = edge.start
            state = step.previous
        }
        path.reverse()

        return path
    }

    private func resolve(_ path: [Edge], afterChinese: Bool) -> [Piece] {
        let fullWidth = punctuationForms(in: path, afterChinese: afterChinese)
        return path.enumerated().map { index, edge in
            var piece = Piece(
                language: edge.language, keys: edge.start..<edge.end, text: edge.text,
                reading: edge.reading, syllableEnds: edge.syllableEnds, isRawKey: edge.isRawKey
            )
            if let key = edge.punctuation {
                piece.language = fullWidth[index] ? .chinese : .english
                piece.text = String(fullWidth[index] ? Self.fullWidthPunctuation[key]! : key)
            }
            return piece
        }
    }

    /// 結尾若是「還沒按聲調、但確實是某個音節開頭」的 1–3 個鍵，回傳它的起點、注音符號，以及前面那段的解讀。
    /// 取最長的那種：打 a、up、go 的當下先顯示成 ㄇ、ㄧㄣ、ㄕㄟ，等下一鍵再決定，不會先顯示英文再跳成中文。
    /// 前面緊接著零散的英文字母時不算（打 abc 不會變成 abㄏ）。
    private func pendingSyllable(in keys: [Character]) -> (start: Int, symbols: String, head: [Edge])? {
        for count in stride(from: min(3, keys.count), through: 1, by: -1) {
            let start = keys.count - count
            let tail = keys[start...]
            guard tail.allSatisfy(Dachen.isSymbolKey) else { continue }
            // 單獨一個標點鍵（, . ;）就是標點，不當成韻母。
            if count == 1, Self.fullWidthPunctuation[keys[start]] != nil { continue }
            guard let symbols = Dachen.symbols(for: tail), lexicon.syllablePrefixes.contains(symbols) else { continue }
            let head = bestPath(Array(keys[..<start]))
            // 前面緊接著零散的英數字：純數字（100元）或兩個以上大寫字母的縮寫（OK、AI）可以接注音，
            // 其他（abc、Gi）多半是詞表沒收的英文字還沒打完，不顯示注音，免得每打一個字母就閃一下。
            let run = head.reversed().prefix { $0.isRawKey && keys[$0.start].isASCII && (keys[$0.start].isLetter || keys[$0.start].isNumber) }
                .map { keys[$0.start] }
            if !run.isEmpty, !run.allSatisfy(\.isNumber), !(run.count >= 2 && run.allSatisfy(\.isUppercase)) { continue }
            // 緊接在英文字母後面、合起來是英文字或英文字的開頭（hel → hello）：多半是英文還沒打完，照字母顯示。
            if start > 0, keys[start - 1].isASCIILetter, tail.allSatisfy(\.isASCIILetter) {
                let letters = String(keys[..<start].reversed().prefix(while: \.isASCIILetter).reversed()) + String(tail)
                if english.isWordOrPrefix(letters) { continue }
            }
            return (start, symbols, head)
        }
        return nil
    }

    /// 決定路徑上每個標點用全形（true）還是半形。
    /// - 夾在英數字中間的（v1.2、app.json、don't）一律半形。
    /// - 右括號跟著對應的左括號。
    /// - 其餘看整串：有中文就全形，純英文就半形。
    private func punctuationForms(in path: [Edge], afterChinese: Bool) -> [Bool] {
        func isWord(_ edge: Edge) -> Bool { edge.punctuation == nil && edge.text != " " }
        func isAlphanumeric(_ character: Character?) -> Bool {
            character.map { $0.isASCII && ($0.isLetter || $0.isNumber) } ?? false
        }
        let words = path.filter(isWord)
        let chineseContext = words.isEmpty ? afterChinese : words.contains { $0.language == .chinese }

        var forms = Array(repeating: false, count: path.count)
        var openBrackets: [(key: Character, fullWidth: Bool)] = []
        for (index, edge) in path.enumerated() {
            guard let key = edge.punctuation else { continue }
            if let opener = Self.closingBrackets[key], let last = openBrackets.last, last.key == opener {
                forms[index] = openBrackets.removeLast().fullWidth
                continue
            }
            let previous = index > 0 && path[index - 1].language == .english && isWord(path[index - 1])
                ? path[index - 1].text.last : nil
            let next = index + 1 < path.count && path[index + 1].language == .english && isWord(path[index + 1])
                ? path[index + 1].text.first : nil
            forms[index] = chineseContext && !(isAlphanumeric(previous) && isAlphanumeric(next))
            if Self.closingBrackets.values.contains(key) { openBrackets.append((key, forms[index])) }
        }
        return forms
    }

    private func edges(in keys: [Character], from start: Int) -> [Edge] {
        var result: [Edge] = []

        let key = keys[start]
        // 非 ASCII 是已經定案的文字（選字窗或符號表選的），原樣輸出，也不讓其他邊跨過它。
        if !key.isASCII {
            return [Edge(start: start, end: start + 1, language: .chinese, text: String(key), score: 0)]
        }

        // 原樣輸出：保證任何輸入都有路可走。
        if let fullWidth = Self.fullWidthPunctuation[key] {
            // 兩條同分的邊，分別接在中文與英文狀態後面，讓標點不影響兩側的語言判斷。
            for language in [Language.chinese, .english] {
                result.append(Edge(
                    start: start, end: start + 1, language: language, text: String(fullWidth),
                    score: weights.punctuation, punctuation: key
                ))
            }
        } else {
            result.append(Edge(
                start: start, end: start + 1, language: .english, text: String(key),
                score: key == " " ? weights.rawSpace : key.isUppercase ? weights.rawUppercase : weights.rawKey,
                isRawKey: true
            ))
        }

        // 中文詞：從這裡一個音節一個音節接下去，每個前綴去查詞庫。
        // 一個詞裡最多修正一個打錯的音節。
        struct Chain {
            var reading = ""
            var ends: [Int] = []
            var penalty = 0.0
            /// 用了通用規則猜的修正（不是使用者自己的紀錄）：要成詞才採用。
            var isGuess = false
        }
        var chains = [Chain()]
        for _ in 0..<Self.maxSyllablesPerWord where !chains.isEmpty {
            var extended: [Chain] = []
            for chain in chains {
                for option in syllableOptions(in: keys, from: chain.ends.last ?? start) {
                    if option.penalty < 0, chain.penalty < 0 { continue }
                    var next = chain
                    next.reading += next.reading.isEmpty ? option.reading : "-" + option.reading
                    next.ends.append(option.end)
                    next.penalty += option.penalty
                    if option.penalty < 0, !option.isPersonal { next.isGuess = true }
                    extended.append(next)
                    // 修正過的音節要連同旁邊的字組成一個夠常見的詞才採用：這是「使用者真的想打這個」最強的證據。
                    // 單一個字的修正太容易把 v3、x86 這類內容改掉。
                    // 用通用規則猜的才需要成詞佐證；個人紀錄可以單字套用。
                    // 但兩種修正都算「修正」，一樣不可以緊接在英數字後面（在 pieces 的動態規劃裡檢查）。
                    if let entry = entries(for: next.reading).first,
                       !next.isGuess || (next.ends.count >= 2 && entry.score >= weights.typoMinWordScore) {
                        // 最常見的同音詞之外，也帶上幾個分數相近的，讓上下文去挑。
                        // 使用者自己選過的詞優先，那時不再讓上下文改掉。
                        let isLearned = userPhrases?.texts(for: next.reading).isEmpty == false
                        let homophones = isLearned || weights.context == 0
                            ? [entry]
                            : entries(for: next.reading).prefix(weights.homophones).filter { entry.score - $0.score <= weights.homophoneMargin }
                        for homophone in homophones {
                            result.append(Edge(
                                start: start, end: option.end, language: .chinese, text: homophone.text,
                                score: homophone.score + next.penalty + weights.chineseWord, reading: next.reading,
                                syllableEnds: next.ends, isCorrection: next.penalty < 0
                            ))
                        }
                    }
                }
            }
            chains = extended
        }

        // 英文詞：必須從字母串的開頭起算，避免從音節中間認出英文字（如「今」rup 裡的 up）。
        // 結尾不限，因為英文後面可以直接接中文（code + ji3）。
        // 中間可以有數字（mp4、x86），但要從字母開始；這類字只有收在常用表裡的才認得。
        if keys[start].isASCIILetter, start == 0 || !keys[start - 1].isASCIILetter {
            var end = start
            while end < keys.count, keys[end].isASCIILetter || keys[end].isASCIIDigit {
                end += 1
                let word = String(keys[start..<end])
                guard let tier = english.tier(of: word) else { continue }
                let score = word.contains(where: \.isNumber) ? weights.alphanumericWord
                    : tier == .common ? weights.commonWord : weights.dictionaryWord
                result.append(Edge(start: start, end: end, language: .english, text: word, score: score))
            }
        }
        return result
    }
}

// MARK: - 打錯容錯

extension Segmenter {
    /// 從某個位置起可以解讀成哪些音節：照標準打法的那一個（如果成立），加上修正手誤後的可能。
    /// 修正三種常見的手誤，各有代價：
    /// 1. 按鍵順序顛倒（su3 打成 s3u、us3）
    /// 2. 漏按聲調就接著打下一個字（su3cl3 打成 sucl3）
    /// 3. 其中一鍵按到隔壁（su3 打成 sy3）
    ///
    /// 修正必須有「使用者確實在打注音」的證據，否則會把 npm、cpu、100 這類內容改成中文：
    /// - 一定要有數字聲調鍵（3 4 6 7）。空白當聲調的一聲不修，因為空白也是英文的分隔。
    /// - 音節裡至少要有一個字母鍵，全是數字與符號的當成數字（3.5、100）。
    /// - 修正後要能和旁邊的字組成常見的詞（在 `edges` 裡檢查）。
    private func syllableOptions(in keys: [Character], from start: Int) -> [SyllableOption] {
        var options: [SyllableOption] = []
        var seen: Set<String> = []
        func add(_ reading: String, _ end: Int, _ penalty: Double) {
            guard lexicon.syllables.contains(reading), seen.insert("\(reading)@\(end)").inserted else { return }
            options.append(SyllableOption(reading: reading, end: end, penalty: penalty))
        }
        if let exact = Dachen.syllable(in: keys, from: start) { add(exact.reading, exact.end, 0) }
        guard weights.typoTolerance else { return options }

        // 使用者自己更正過兩次以上的錯：直接當成他想打的那個音節。
        if let typos {
            for length in 2...5 where start + length <= keys.count {
                guard let intended = typos.intended(for: String(keys[start..<start + length])),
                      let syllable = Dachen.syllable(in: Array(intended), from: 0), syllable.end == intended.count,
                      lexicon.syllables.contains(syllable.reading),
                      seen.insert("\(syllable.reading)@\(start + length)").inserted else { continue }
                options.append(SyllableOption(
                    reading: syllable.reading, end: start + length, penalty: weights.typoPersonal, isPersonal: true
                ))
            }
        }

        func isToneDigit(_ key: Character) -> Bool { key != " " && Dachen.tones[key] != nil }
        func hasLetterSymbol(_ range: Range<Int>) -> Bool {
            keys[range].contains { Dachen.isSymbolKey($0) && $0.isLetter }
        }
        // 聲調鍵開頭的不修：那個聲調多半屬於前一個字。
        guard start < keys.count, Dachen.tones[keys[start]] == nil else { return options }

        // 1. 順序顛倒：接下來 2–4 個鍵剛好是「聲母、介音、韻母各至多一個＋一個聲調」，只是順序不對。
        for length in 2...4 where start + length <= keys.count {
            let range = start..<start + length
            guard keys[range].contains(where: isToneDigit), hasLetterSymbol(range),
                  let reading = Dachen.syllable(fromUnordered: keys[range]) else { continue }
            add(reading, range.upperBound, weights.typoOrder)
        }

        // 2. 漏按聲調：2–3 個注音鍵後面緊接著一個打對的、帶數字聲調的音節。
        for length in 2...3 where start + length < keys.count {
            let range = start..<start + length
            // 剛好是英文字的（up、so）不當成漏聲調。
            guard hasLetterSymbol(range), english.tier(of: String(keys[range])) == nil,
                  let symbols = Dachen.symbols(for: keys[range]),
                  let next = Dachen.syllable(in: keys, from: range.upperBound),
                  lexicon.syllables.contains(next.reading), isToneDigit(keys[next.end - 1]) else { continue }
            for tone in Dachen.tones.values { add(symbols + tone, range.upperBound, weights.typoMissingTone) }
        }

        // 3. 按到隔壁鍵：把其中一個注音鍵換成鍵盤上相鄰的鍵後，照標準打法能成立。聲調鍵本身不換。
        // 只修字母鍵：數字鍵按錯和「本來就想打數字」（x86、v3）分不出來。
        for offset in 0..<3 where start + offset < keys.count && keys[start + offset].isLetter {
            for neighbor in Dachen.neighbors[keys[start + offset]] ?? [] where Dachen.isSymbolKey(neighbor) {
                var corrected = keys
                corrected[start + offset] = neighbor
                guard let syllable = Dachen.syllable(in: corrected, from: start), syllable.end - 1 > start + offset,
                      isToneDigit(keys[syllable.end - 1]), hasLetterSymbol(start..<syllable.end) else { continue }
                add(syllable.reading, syllable.end, weights.typoNeighbor)
            }
        }
        return options
    }
}

private extension Character {
    var isASCIILetter: Bool { isASCII && isLetter }
    var isASCIIDigit: Bool { isASCII && isNumber }
}
