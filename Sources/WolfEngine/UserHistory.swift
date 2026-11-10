import Foundation

/// 使用者實際送出過的內容裡，「某段前文 → 接下來的詞」出現幾次，用來預測接下來要打什麼。
/// 只存在本機。參考型別，所有輸入視窗共用。
public final class UserHistory: @unchecked Sendable {
    private let lock = NSLock()
    private var following: [String: [String: Int]] = [:]
    private let file: JSONFile<[String: [String: Int]]>

    /// 出現至少這麼多次才拿來預測，避免只打過一次的內容一直跳出來。
    public static let minimumCount = 2
    /// 最多記這麼多個前文；超過時丟掉總次數最少的一成。
    public static let maximumContexts = 5000
    /// 每個前文最多記這麼多種後續；超過時丟掉次數最少的。
    public static let maximumFollowersPerContext = 16
    /// 太長的後續不記（多半是整句英文或貼上的內容）。
    public static let maximumFollowerLength = 16

    /// 代表「一句話的開頭」的前文。不會跟真的前文撞名（那些不是空的就是字）。
    public static let sentenceStart = "^"

    /// 目前記了幾個前文。
    public var contextCount: Int { lock.withLock { following.count } }

    /// - Parameter fileURL: 儲存位置（JSON）；nil 表示只放在記憶體（測試用）。
    public init(fileURL: URL? = nil) {
        file = JSONFile(url: fileURL)
        following = file.load() ?? [:]
    }

    /// 目前所有的用詞紀錄（評測工具用）。
    public var all: [String: [String: Int]] { lock.withLock { following } }

    /// 等排定的寫入完成。
    public func flush() { file.flush() }

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
        // 句子的第一個詞也記下來，送出一句之後可以預測下一句怎麼開頭。
        if let first = units.first { pairs.append((Self.sentenceStart, units[0..<first.wordEnd].map(\.text).joined())) }
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
        lock.withLock {
            for (key, next) in pairs where next.count <= Self.maximumFollowerLength {
                var followers = following[key, default: [:]]
                followers[next, default: 0] += 1
                if followers.count > Self.maximumFollowersPerContext,
                   let weakest = followers.filter({ $0.key != next }).min(by: { ($0.value, $1.key) < ($1.value, $0.key) }) {
                    followers[weakest.key] = nil
                }
                following[key] = followers
            }
            if following.count > Self.maximumContexts {
                let keep = following.sorted { $0.value.values.reduce(0, +) > $1.value.values.reduce(0, +) }
                    .prefix(Self.maximumContexts * 9 / 10)
                following = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
            }
        }
        file.save { [self] in lock.withLock { following } }
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
