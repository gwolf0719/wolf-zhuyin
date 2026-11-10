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
        /// 中英切換一次的代價。
        public var languageSwitch = -1.0
        public init() {}
    }

    public let lexicon: Lexicon
    /// 使用者選過的字詞；有設定時，轉換與候選都優先採用。
    public var userPhrases: UserPhrases?
    public let english: EnglishWords
    public var weights = Weights()

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
        /// 原樣輸出的單一按鍵。
        var isRawKey = false
        /// 標點邊：不改變前面的語言狀態，全形或半形等整條路徑定案後再決定。
        var punctuation: Character? = nil
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
        /// 無法解讀、原樣輸出的單一按鍵。
        var isRawKey = false
        /// 結尾打到一半的音節。
        var isPending = false
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
        for piece in pieces(Array(input), afterChinese: afterChinese, showPending: showPending) {
            if let last = segments.last, last.language == piece.language {
                segments[segments.count - 1] = Segment(
                    language: piece.language,
                    keys: last.keys.lowerBound..<piece.keys.upperBound,
                    text: last.text + piece.text
                )
            } else {
                segments.append(Segment(language: piece.language, keys: piece.keys, text: piece.text))
            }
        }
        return segments
    }

    /// 結尾那幾個中文字的其他選擇：先列較長的詞，再列單字。結尾不是中文時回傳空陣列。
    public func candidates(_ input: String, afterChinese: Bool = true) -> [Candidate] {
        let keys = Array(input)
        let all = pieces(keys, afterChinese: afterChinese, showPending: false)
        // 把結尾連續的中文詞拆回一個個音節。
        var syllables: [(reading: String, start: Int)] = []
        for piece in all.reversed() {
            guard let reading = piece.reading else { break }
            var position = piece.keys.lowerBound
            var parsed: [(String, Int)] = []
            for _ in reading.split(separator: "-") {
                guard let syllable = Dachen.syllable(in: keys, from: position) else { break }
                parsed.append((syllable.reading, position))
                position = syllable.end
            }
            syllables.insert(contentsOf: parsed, at: 0)
        }
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

    /// 組字區要顯示的文字，以及游標可以停的位置（按鍵位置 ↔ 文字位置）。
    /// 中文一個字停一次、英文一個字母停一次，不會停在一個字的按鍵中間。
    public func layout(_ input: String, afterChinese: Bool = true) -> (text: String, stops: [(key: Int, offset: Int)]) {
        let keys = Array(input)
        var text = ""
        var stops = [(key: 0, offset: 0)]
        for piece in pieces(keys, afterChinese: afterChinese, showPending: true) {
            let base = text.count
            text += piece.text
            if let reading = piece.reading, reading.split(separator: "-").count == piece.text.count {
                var position = piece.keys.lowerBound
                for index in 1...piece.text.count {
                    guard let syllable = Dachen.syllable(in: keys, from: position) else { break }
                    position = syllable.end
                    stops.append((position, base + index))
                }
            } else if piece.language == .english, piece.keys.count == piece.text.count {
                for index in 1...piece.text.count { stops.append((piece.keys.lowerBound + index, base + index)) }
            }
            if stops.last?.key != piece.keys.upperBound { stops.append((piece.keys.upperBound, text.count)) }
        }
        return (text, stops)
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
        if let reading = last.reading {
            var position = last.keys.lowerBound
            var lastSyllableStart = position
            for _ in reading.split(separator: "-") {
                guard let syllable = Dachen.syllable(in: keys, from: position) else { break }
                lastSyllableStart = position
                position = syllable.end
            }
            return keys.count - lastSyllableStart
        }
        guard last.isRawKey, keys[last.keys.lowerBound] != " " else { return 1 }
        let run = all.reversed().prefix { $0.isRawKey && keys[$0.keys.lowerBound] != " " }
        let looksLikeMistypedZhuyin = run.contains { !keys[$0.keys.lowerBound].isLetter }
        return looksLikeMistypedZhuyin ? run.count : 1
    }

    func pieces(_ keys: [Character], afterChinese: Bool, showPending: Bool) -> [Piece] {
        guard !keys.isEmpty else { return [] }

        // best[位置][語言]：走到該位置、最後一條邊是該語言時的最高分。
        let languages: [Language] = [.chinese, .english]
        var best = Array(repeating: [Double](repeating: -.infinity, count: 2), count: keys.count + 1)
        var back = Array(repeating: [(edge: Edge, previous: Int)?](repeating: nil, count: 2), count: keys.count + 1)
        best[0] = [0, 0]

        for position in 0..<keys.count {
            for edge in edges(in: keys, from: position) {
                let to = edge.language == .chinese ? 0 : 1
                for from in 0..<2 where best[position][from] > -.infinity {
                    // 標點邊維持前一個語言狀態，不算切換。
                    if edge.punctuation != nil, languages[from] != edge.language { continue }
                    let switched = position > 0 && languages[from] != edge.language
                    let score = best[position][from] + edge.score + (switched ? weights.languageSwitch : 0)
                    if score > best[edge.end][to] {
                        best[edge.end][to] = score
                        back[edge.end][to] = (edge, from)
                    }
                }
            }
        }

        var path: [Edge] = []
        var position = keys.count
        var state = best[position][0] >= best[position][1] ? 0 : 1
        while position > 0, let step = back[position][state] {
            path.append(step.edge)
            position = step.edge.start
            state = step.previous
        }
        path.reverse()

        if showPending, let pending = pendingSyllable(in: keys, path: path) {
            // 結尾是打到一半的音節：前面照常處理，結尾顯示注音符號。
            let head = Array(path.prefix { $0.start < pending.start })
            var result = resolve(head, afterChinese: afterChinese)
            result.append(Piece(language: .chinese, keys: pending.start..<keys.count, text: pending.symbols, isPending: true))
            return result
        }
        return resolve(path, afterChinese: afterChinese)
    }

    private func resolve(_ path: [Edge], afterChinese: Bool) -> [Piece] {
        let fullWidth = punctuationForms(in: path, afterChinese: afterChinese)
        return path.enumerated().map { index, edge in
            var piece = Piece(
                language: edge.language, keys: edge.start..<edge.end, text: edge.text,
                reading: edge.reading, isRawKey: edge.isRawKey
            )
            if let key = edge.punctuation {
                piece.language = fullWidth[index] ? .chinese : .english
                piece.text = String(fullWidth[index] ? Self.fullWidthPunctuation[key]! : key)
            }
            return piece
        }
    }

    /// 結尾若是「還沒按聲調、但確實是某個音節開頭」的 1–3 個鍵，回傳它的起點與注音符號。
    /// 只在這幾個鍵前面不是其他零散英數字時成立，所以打 abc 不會變成 abㄏ。
    private func pendingSyllable(in keys: [Character], path: [Edge]) -> (start: Int, symbols: String)? {
        var count = 0
        for edge in path.reversed() {
            guard edge.end - edge.start == 1, edge.isRawKey || edge.punctuation != nil,
                  Dachen.isSymbolKey(keys[edge.start]) else { break }
            count += 1
        }
        guard (1...3).contains(count) else { return nil }
        let start = keys.count - count
        // 單獨一個標點鍵（, . ;）就是標點，不當成韻母。
        if count == 1, Self.fullWidthPunctuation[keys[start]] != nil { return nil }
        if start > 0, let previous = path.last(where: { $0.end == start }),
           previous.isRawKey, keys[start - 1].isASCII, keys[start - 1].isLetter || keys[start - 1].isNumber {
            return nil
        }
        guard let symbols = Dachen.symbols(for: keys[start...]), lexicon.syllablePrefixes.contains(symbols) else { return nil }
        return (start, symbols)
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

        // 中文詞：從這裡連續解析出的音節，每個前綴去查詞庫。
        var reading = ""
        var position = start
        for _ in 0..<Self.maxSyllablesPerWord {
            guard let syllable = Dachen.syllable(in: keys, from: position),
                  lexicon.syllables.contains(syllable.reading) else { break }
            reading += reading.isEmpty ? syllable.reading : "-" + syllable.reading
            position = syllable.end
            if let entry = entries(for: reading).first {
                result.append(Edge(start: start, end: position, language: .chinese, text: entry.text, score: entry.score, reading: reading))
            }
        }

        // 英文詞：必須從字母串的開頭起算，避免從音節中間認出英文字（如「今」rup 裡的 up）。
        // 結尾不限，因為英文後面可以直接接中文（code + ji3）。
        if start == 0 || !keys[start - 1].isASCIILetter {
            var end = start
            while end < keys.count, keys[end].isASCIILetter {
                end += 1
                let word = String(keys[start..<end])
                guard let tier = english.tier(of: word) else { continue }
                let score = tier == .common ? weights.commonWord : weights.dictionaryWord
                result.append(Edge(start: start, end: end, language: .english, text: word, score: score))
            }
        }
        return result
    }
}

private extension Character {
    var isASCIILetter: Bool { isASCII && isLetter }
}
