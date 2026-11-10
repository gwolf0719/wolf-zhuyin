import Foundation

/// 使用者個人的打錯習慣：「打錯的按鍵 → 原本想打的按鍵」各出現幾次。
/// 來源是「退格刪掉、馬上重打成很像的東西」這個動作。只存在本機。
public final class UserTypos: @unchecked Sendable {
    private let lock = NSLock()
    private var corrections: [String: [String: Int]] = [:] {
        didSet { cachedHabits = Self.habits(in: corrections) }
    }
    /// 每打一個鍵都會查好幾次，所以存起來，紀錄變動時才重算。
    private var cachedHabits: Set<Kind> = []
    private let file: JSONFile<[String: [String: Int]]>

    /// 同一個錯至少更正過這麼多次才自動套用。打錯的按鍵裡有數字聲調鍵（3 4 6 7）時一次就套用：
    /// 那串按鍵既不是正確的音節、也不是英文字（學的時候檢查過），又帶著聲調，幾乎一定是在打注音。
    /// 空白當一聲的要兩次，因為空白也是英文的分隔。
    public static let minimumCount = 2
    public static let minimumCountWithToneDigit = 1
    /// 某一類打錯（順序顛倒、多按一鍵、漏按一鍵）累計更正這麼多次，就當成使用者的習慣：
    /// 同類的打錯就算沒看過，也不必和旁邊的字成詞就修正。
    public static let habitThreshold = 3

    /// 打錯的類型。
    public enum Kind: Sendable, CaseIterable {
        /// 同樣的鍵、順序不對（uv84 → vu84）。
        case reordered
        /// 多按了一個鍵（urup4 → rup4）。
        case extraKey
        /// 少按了一個鍵（ho4 → hjo4）。
        case missingKey
    }
    /// 最多記這麼多種打錯的按鍵；超過時丟掉最少發生的。
    public static let maximumEntries = 2000

    /// - Parameter fileURL: 儲存位置（JSON）；nil 表示只放在記憶體（測試用）。
    public init(fileURL: URL? = nil) {
        file = JSONFile(url: fileURL)
        corrections = file.load() ?? [:]
        // 初始化時 didSet 不會觸發，要自己算。
        cachedHabits = Self.habits(in: corrections)
    }

    /// 只放在記憶體、內容直接給定（評測工具用）。
    public init(corrections: [String: [String: Int]]) {
        file = JSONFile(url: nil)
        self.corrections = corrections
        cachedHabits = Self.habits(in: corrections)
    }

    /// 目前所有的更正紀錄。
    public var all: [String: [String: Int]] { lock.withLock { corrections } }

    /// 刪掉一筆打錯紀錄。
    public func remove(mistyped: String, intended: String) {
        lock.withLock {
            corrections[mistyped]?[intended] = nil
            if corrections[mistyped]?.isEmpty == true { corrections[mistyped] = nil }
        }
        file.save { [self] in lock.withLock { corrections } }
    }

    /// 等排定的寫入完成。
    public func flush() { file.flush() }

    public func learn(mistyped: String, intended: String) {
        guard mistyped.count <= 8, intended.count <= 8 else { return }
        lock.withLock {
            corrections[mistyped, default: [:]][intended, default: 0] += 1
            if corrections.count > Self.maximumEntries {
                let keep = corrections.sorted { $0.value.values.reduce(0, +) > $1.value.values.reduce(0, +) }
                    .prefix(Self.maximumEntries * 9 / 10)
                corrections = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
            }
        }
        file.save { [self] in lock.withLock { corrections } }
    }

    /// 這串按鍵若是使用者常犯的錯，回傳他原本想打的按鍵。
    public func intended(for mistyped: String) -> String? {
        lock.withLock {
            let minimum = mistyped.contains { "3467".contains($0) } ? Self.minimumCountWithToneDigit : Self.minimumCount
            guard let best = corrections[mistyped]?.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }),
                  best.value >= minimum else { return nil }
            return best.key
        }
    }

    /// 使用者習慣犯的打錯類型：同一類累計更正至少 `habitThreshold` 次。
    public var habits: Set<Kind> { lock.withLock { cachedHabits } }

    private static func habits(in corrections: [String: [String: Int]]) -> Set<Kind> {
        var counts: [Kind: Int] = [:]
        for (mistyped, intended) in corrections {
            for (text, count) in intended {
                if let kind = kind(Array(mistyped), Array(text)) { counts[kind, default: 0] += count }
            }
        }
        return Set(counts.filter { $0.value >= habitThreshold }.keys)
    }

    static func kind(_ mistyped: [Character], _ intended: [Character]) -> Kind? {
        guard mistyped != intended else { return nil }
        if mistyped.sorted() == intended.sorted() { return .reordered }
        func dropsOne(_ longer: [Character], _ shorter: [Character]) -> Bool {
            longer.count == shorter.count + 1 && longer.indices.contains { index in
                var trimmed = longer
                trimmed.remove(at: index)
                return trimmed == shorter
            }
        }
        if dropsOne(mistyped, intended) { return .extraKey }
        if dropsOne(intended, mistyped) { return .missingKey }
        return nil
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
