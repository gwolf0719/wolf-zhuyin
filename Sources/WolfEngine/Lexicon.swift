import Foundation

/// 中文詞庫：小麥注音的 `data.txt`（每行「讀音 詞 log10 機率」）。
public struct Lexicon: Sendable {
    public struct Entry: Sendable {
        public let text: String
        public let score: Double

        public init(text: String, score: Double) {
            self.text = text
            self.score = score
        }
    }

    /// 讀音 → 候選詞，依分數由高到低。
    public private(set) var entries: [String: [Entry]] = [:]
    /// 詞庫裡出現過的所有單一音節。
    public private(set) var syllables: Set<String> = []
    /// 所有音節去掉聲調後的每一種開頭（ㄋ、ㄋㄧ、ㄋㄧㄠ…），用來判斷「打到一半的音節」。
    public private(set) var syllablePrefixes: Set<String> = []
    /// 詞 → 最常見的讀音（評測時把文字轉回按鍵用）。
    private(set) var readings: [String: (reading: String, score: Double)] = [:]

    public init(contentsOf url: URL) throws {
        let content = try String(contentsOf: url, encoding: .utf8)
        for line in content.split(separator: "\n") {
            guard let first = line.first, first != "#", first != "_" else { continue }
            let fields = line.split(separator: " ")
            guard fields.count == 3, let score = Double(fields[2]) else { continue }
            let reading = String(fields[0])
            let text = String(fields[1])
            entries[reading, default: []].append(Entry(text: text, score: score))
            if (readings[text]?.score ?? -.infinity) < score {
                readings[text] = (reading, score)
            }
            for syllable in fields[0].split(separator: "-") {
                syllables.insert(String(syllable))
            }
        }
        for syllable in syllables {
            let symbols = syllable.filter { !"ˊˇˋ˙".contains($0) }
            for length in 1...max(symbols.count, 1) where !symbols.isEmpty {
                syllablePrefixes.insert(String(symbols.prefix(length)))
            }
        }
        for key in entries.keys {
            entries[key]!.sort { $0.score > $1.score }
        }
    }
}
