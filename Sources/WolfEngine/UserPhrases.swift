import Foundation

/// 使用者在選字窗選過的字詞。同一個讀音下，最近選的排最前面，轉換時優先採用。
/// 是參考型別：所有輸入視窗共用同一份，在 A 視窗學到的，B 視窗馬上生效。
public final class UserPhrases: @unchecked Sendable {
    private let lock = NSLock()
    private var phrases: [String: [String]] = [:]
    private let file: JSONFile<[String: [String]]>
    /// 同一個讀音最多記這麼多個選擇。
    public static let maximumPerReading = 10

    /// - Parameter fileURL: 儲存位置（JSON）；nil 表示只放在記憶體（測試用）。
    public init(fileURL: URL? = nil) {
        file = JSONFile(url: fileURL)
        phrases = file.load() ?? [:]
    }

    /// 等排定的寫入完成。
    public func flush() { file.flush() }

    /// 這個讀音下使用者選過的字詞，最近選的在前。
    public func texts(for reading: String) -> [String] {
        lock.withLock { phrases[reading] ?? [] }
    }

    public func learn(reading: String, text: String) {
        lock.withLock {
            var texts = phrases[reading] ?? []
            texts.removeAll { $0 == text }
            texts.insert(text, at: 0)
            phrases[reading] = Array(texts.prefix(Self.maximumPerReading))
        }
        file.save { [self] in lock.withLock { phrases } }
    }
}
