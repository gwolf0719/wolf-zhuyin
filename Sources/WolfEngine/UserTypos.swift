import Foundation

/// 使用者個人的打錯習慣：「打錯的按鍵 → 原本想打的按鍵」各出現幾次。
/// 來源是「退格刪掉、馬上重打成很像的東西」這個動作。只存在本機。
public final class UserTypos: @unchecked Sendable {
    private let lock = NSLock()
    private var corrections: [String: [String: Int]] = [:]
    private let fileURL: URL?

    /// 同一個錯至少更正過這麼多次才自動套用。
    public static let minimumCount = 2

    /// - Parameter fileURL: 儲存位置（JSON）；nil 表示只放在記憶體（測試用）。
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            corrections = stored
        }
    }

    public func learn(mistyped: String, intended: String) {
        let snapshot: [String: [String: Int]] = lock.withLock {
            corrections[mistyped, default: [:]][intended, default: 0] += 1
            return corrections
        }
        guard let fileURL else { return }
        // 寫入失敗不影響打字。
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// 這串按鍵若是使用者常犯的錯，回傳他原本想打的按鍵。
    public func intended(for mistyped: String) -> String? {
        lock.withLock {
            guard let best = corrections[mistyped]?.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }),
                  best.value >= Self.minimumCount else { return nil }
            return best.key
        }
    }

    /// 兩串按鍵是否像「同一個音節打錯了」：順序不同、差一個鍵、少一個鍵或多一個鍵。
    /// 用來分辨「更正手誤」和「改變主意換一個字」。
    static func looksLikeSameSyllable(_ mistyped: [Character], _ intended: [Character]) -> Bool {
        guard mistyped != intended else { return false }
        if mistyped.sorted() == intended.sorted() { return true }
        if mistyped.count == intended.count {
            return zip(mistyped, intended).filter { $0 != $1 }.count == 1
        }
        let (shorter, longer) = mistyped.count < intended.count ? (mistyped, intended) : (intended, mistyped)
        guard longer.count == shorter.count + 1 else { return false }
        return longer.indices.contains { index in
            var trimmed = longer
            trimmed.remove(at: index)
            return trimmed == shorter
        }
    }
}
