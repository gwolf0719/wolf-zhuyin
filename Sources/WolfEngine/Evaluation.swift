/// 評測：把「期望輸出的句子」反推成使用者會按的鍵，再看引擎能不能還原。
public struct Evaluation: Sendable {
    public struct Typed: Sendable {
        public let keys: String
        /// 每個按鍵是否屬於中文。
        public let isChinese: [Bool]
    }

    public struct Outcome: Sendable {
        public let expected: String
        public let keys: String
        public let actual: String
        /// 每個按鍵的中英判斷都正確。
        public let languageCorrect: Bool
        /// 輸出文字與期望完全相同（含選字）。
        public var textCorrect: Bool { expected == actual }
    }

    public let segmenter: Segmenter

    public init(segmenter: Segmenter) {
        self.segmenter = segmenter
    }

    /// 全形標點 → 按鍵。同一個全形符號有兩顆鍵時取不必按 Shift 的那顆。
    private static let keyForFullWidth: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (key, fullWidth) in Segmenter.fullWidthPunctuation where key != "<" && key != ">" {
            map[fullWidth] = key
        }
        return map
    }()

    /// 模擬打字：中文照詞庫讀音轉成大千按鍵，其餘字元原樣輸入。詞庫查不到的字回傳 nil。
    public func type(_ text: String) -> Typed? {
        let characters = Array(text)
        var keys = ""
        var isChinese: [Bool] = []
        var index = 0
        while index < characters.count {
            if characters[index].isASCII {
                keys.append(characters[index])
                isChinese.append(false)
                index += 1
                continue
            }
            if let key = Self.keyForFullWidth[characters[index]] {
                keys.append(key)
                isChinese.append(true)
                index += 1
                continue
            }
            // 最長詞優先，讓多音字盡量跟著詞走。
            var matched = false
            for length in stride(from: min(8, characters.count - index), through: 1, by: -1) {
                let word = String(characters[index..<index + length])
                guard let reading = segmenter.lexicon.readings[word]?.reading,
                      let wordKeys = Dachen.keys(forReading: reading) else { continue }
                keys += wordKeys
                isChinese += Array(repeating: true, count: wordKeys.count)
                index += length
                matched = true
                break
            }
            if !matched { return nil }
        }
        return Typed(keys: keys, isChinese: isChinese)
    }

    public func run(_ expected: String) -> Outcome? {
        guard let typed = type(expected) else { return nil }
        let segments = segmenter.segment(typed.keys)
        var isChinese = Array(repeating: false, count: typed.keys.count)
        for segment in segments where segment.language == .chinese {
            for index in segment.keys { isChinese[index] = true }
        }
        return Outcome(
            expected: expected,
            keys: typed.keys,
            actual: segments.map(\.text).joined(),
            languageCorrect: isChinese == typed.isChinese
        )
    }

    /// 打字過程的穩定度：一鍵一鍵打的時候，已經顯示成完整中文字或英文的按鍵，後來又被改判成另一種語言幾次。
    /// 打到一半、顯示成注音符號的不算（那本來就還沒定）。
    public struct Stability: Sendable {
        public let keys: String
        /// 每一步組字區顯示的文字。
        public let steps: [String]
        /// 改判的次數，以及每次是在打第幾鍵時、哪個按鍵。
        public let flips: [(step: Int, key: Int, toChinese: Bool)]
    }

    public func stability(_ expected: String) -> Stability? {
        guard let typed = type(expected) else { return nil }
        let keys = Array(typed.keys)
        var last: [Bool?] = Array(repeating: nil, count: keys.count)
        var steps: [String] = []
        var flips: [(step: Int, key: Int, toChinese: Bool)] = []
        for length in 1...keys.count {
            let pieces = segmenter.pieces(Array(keys[..<length]), afterChinese: true, showPending: true)
            steps.append(pieces.map(\.text).joined())
            for piece in pieces where !piece.isPending {
                // 標點、空白不算語言判斷；只看中文字和英數字。
                guard piece.reading != nil || piece.text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { continue }
                let isChinese = piece.language == .chinese
                for key in piece.keys {
                    if let previous = last[key], previous != isChinese { flips.append((length, key, isChinese)) }
                    last[key] = isChinese
                }
            }
        }
        return Stability(keys: typed.keys, steps: steps, flips: flips)
    }
}
