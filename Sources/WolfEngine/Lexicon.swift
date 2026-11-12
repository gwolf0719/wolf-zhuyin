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
    /// 詞的開頭 → 常見的後續，最常見的在前（「不好」→「意思」…），給預測用。開頭至少兩個字。
    public private(set) var continuations: [String: [String]] = [:]
    private static let continuationsPerPrefix = 6
    /// 當後續沒有意義的字：幾乎什麼詞後面都能接，推薦了等於沒推薦。
    private static let weakContinuations: Set<String> = ["的", "了", "是", "在", "有", "和", "與", "及", "人", "說", "來", "去", "用", "會", "要", "到", "上", "中", "裡"]
    /// 詞 → 最常見的讀音（評測時把文字轉回按鍵用）。
    private(set) var readings: [String: (reading: String, score: Double)] = [:]

    /// 詞庫有沒有收這個字。簡體字、日文漢字不在裡面，用來濾掉本機模型偶爾冒出來的簡體。
    public func contains(_ character: Character) -> Bool { readings[String(character)] != nil }

    public static let extraCharactersFile = "extra-characters.txt"

    public init(contentsOf url: URL) throws {
        var content = try String(contentsOf: url, encoding: .utf8)
        // 同一個資料夾的補充表：詞庫沒收的罕用字（饍…），分數最低，只排在選字窗最後。沒有這個檔也能用。
        let extra = url.deletingLastPathComponent().appendingPathComponent(Self.extraCharactersFile)
        if let more = try? String(contentsOf: extra, encoding: .utf8) { content += "\n" + more }
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
        var found: [String: [(rest: String, score: Double)]] = [:]
        for (text, entry) in readings where text.count >= 3 {
            let characters = Array(text)
            for length in 2..<characters.count {
                let rest = String(characters[length...])
                guard !Self.weakContinuations.contains(rest) else { continue }
                found[String(characters[..<length]), default: []].append((rest, entry.score))
            }
        }
        continuations = found.mapValues { options in
            // 分數相同時照字典序，讓結果固定。
            options.sorted { ($0.score, $1.rest) > ($1.score, $0.rest) }.prefix(Self.continuationsPerPrefix).map(\.rest)
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
