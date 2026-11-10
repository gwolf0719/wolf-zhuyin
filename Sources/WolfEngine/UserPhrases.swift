import Foundation

/// 使用者在選字窗選過的字詞。同一個讀音下，最近選的排最前面，轉換時優先採用。
/// 是參考型別：所有輸入視窗共用同一份，在 A 視窗學到的，B 視窗馬上生效。
public final class UserPhrases: @unchecked Sendable {
    private let lock = NSLock()
    private var phrases: [String: [String]] = [:]
    private let fileURL: URL?

    /// - Parameter fileURL: 儲存位置（JSON）；nil 表示只放在記憶體（測試用）。
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([String: [String]].self, from: data) {
            phrases = stored
        }
    }

    /// 這個讀音下使用者選過的字詞，最近選的在前。
    public func texts(for reading: String) -> [String] {
        lock.withLock { phrases[reading] ?? [] }
    }

    public func learn(reading: String, text: String) {
        let snapshot: [String: [String]] = lock.withLock {
            var texts = phrases[reading] ?? []
            texts.removeAll { $0 == text }
            texts.insert(text, at: 0)
            phrases[reading] = texts
            return phrases
        }
        guard let fileURL else { return }
        // 寫入失敗不影響打字；下次選字會再寫一次。
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
