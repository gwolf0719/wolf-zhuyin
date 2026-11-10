import Foundation

/// 使用者實際送出過的內容裡，「某段前文 → 接下來的詞」出現幾次，用來預測接下來要打什麼。
/// 只存在本機。參考型別，所有輸入視窗共用。
public final class UserHistory: @unchecked Sendable {
    private let lock = NSLock()
    private var following: [String: [String: Int]] = [:]
    private let fileURL: URL?

    /// 出現至少這麼多次才拿來預測，避免只打過一次的內容一直跳出來。
    public static let minimumCount = 2

    /// - Parameter fileURL: 儲存位置（JSON）；nil 表示只放在記憶體（測試用）。
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            following = stored
        }
    }

    /// 查詢用的前文：結尾是英文字就用那個字；結尾是中文就用最後兩個字，再退而求其次用最後一個字。
    static func contextKeys(for words: some BidirectionalCollection<String>) -> [String] {
        guard let last = words.last else { return [] }
        if last.allSatisfy(\.isASCII) { return [last] }
        var run = ""
        for word in words.reversed() {
            guard !word.allSatisfy(\.isASCII) else { break }
            run = word + run
            if run.count >= 2 { break }
        }
        return run.count >= 2 ? [String(run.suffix(2)), String(run.suffix(1))] : [run]
    }

    /// 記下一句話。中文以「字」為位置來記：每個字的位置都記下「前兩個字 → 這個詞剩下的部分」。
    /// 不直接用詞當單位，因為同一段字有時被當成一個詞、有時被拆開（不好吃／不＋好吃）。
    public func record(_ words: [String]) {
        // 攤平成單位：中文一字一個、英文一個字一個；每個單位記住它所屬的詞在哪裡結束。
        var units: [(text: String, isChinese: Bool, wordEnd: Int)] = []
        for word in words {
            if word.allSatisfy(\.isASCII) {
                units.append((word, false, units.count + 1))
            } else {
                let end = units.count + word.count
                for character in word { units.append((String(character), true, end)) }
            }
        }
        var pairs: [(String, String)] = []
        for index in units.indices.dropFirst() {
            let next = units[index..<units[index].wordEnd].map(\.text).joined()
            let previous = units[index - 1]
            if !previous.isChinese {
                pairs.append((previous.text, next))
            } else {
                pairs.append((previous.text, next))
                if index >= 2, units[index - 2].isChinese { pairs.append((units[index - 2].text + previous.text, next)) }
            }
        }
        guard !pairs.isEmpty else { return }
        let snapshot: [String: [String: Int]] = lock.withLock {
            for (key, next) in pairs { following[key, default: [:]][next, default: 0] += 1 }
            return following
        }
        guard let fileURL else { return }
        // 寫入失敗不影響打字。
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// 這段前文後面常接什麼，最常見的在前。次數相同時照字典序，讓結果固定。
    public func likely(after words: [String]) -> [String] {
        lock.withLock {
            var result: [String] = []
            for key in Self.contextKeys(for: words) {
                let ranked = (following[key] ?? [:]).filter { $0.value >= Self.minimumCount }
                    .sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
                for next in ranked where !result.contains(next) { result.append(next) }
            }
            return result
        }
    }
}
