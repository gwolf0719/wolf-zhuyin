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
}
