/// 學習紀錄的一筆，給「學習紀錄」視窗列出與刪除用。
public struct LearnedEntry: Sendable, Hashable {
    public enum Kind: Int, Sendable, CaseIterable {
        /// 選字窗選過的字詞。
        case phrase
        /// 打過的詞序（預測用）。
        case history
        /// 打錯與更正。
        case typo
    }

    public let kind: Kind
    /// 紀錄裡的原始鍵與值，刪除時用。
    public let key: String
    public let value: String
    /// 出現幾次；選字紀錄沒有次數，是 0。
    public let count: Int
    /// 這筆紀錄是否已經在影響打字（次數到門檻了）。
    public let isActive: Bool

    /// 顯示用的左欄：讀音、前文、打錯的按鍵。
    public var left: String {
        switch kind {
        case .phrase: return key.replacingOccurrences(of: "-", with: " ")
        case .history: return key == UserHistory.sentenceStart ? "（句子開頭）" : key
        case .typo: return key.replacingOccurrences(of: " ", with: "␣")
        }
    }

    /// 顯示用的右欄：選的字詞、接的詞、原本想打的注音。
    public var right: String {
        guard kind == .typo else { return value }
        let keys = Array(value)
        let reading = Dachen.syllable(in: keys, from: 0).flatMap { $0.end == keys.count ? $0.reading : nil }
        let typed = value.replacingOccurrences(of: " ", with: "␣")
        return reading.map { "\($0)（\(typed)）" } ?? typed
    }
}

extension Preferences.Stores {
    /// 某一類的所有紀錄：已經在影響打字的排前面，其次次數多的在前。
    public func entries(_ kind: LearnedEntry.Kind) -> [LearnedEntry] {
        var result: [LearnedEntry] = []
        switch kind {
        case .phrase:
            for (reading, texts) in phrases.all {
                for (index, text) in texts.enumerated() {
                    // 同一個讀音只有最近選的那個會被優先採用。
                    result.append(LearnedEntry(kind: kind, key: reading, value: text, count: 0, isActive: index == 0))
                }
            }
        case .history:
            for (context, followers) in history.all {
                for (next, count) in followers {
                    result.append(LearnedEntry(
                        kind: kind, key: context, value: next, count: count, isActive: count >= UserHistory.minimumCount
                    ))
                }
            }
        case .typo:
            for (mistyped, intended) in typos.all {
                for (target, _) in intended {
                    result.append(LearnedEntry(
                        kind: kind, key: mistyped, value: target, count: intended[target] ?? 0,
                        isActive: typos.intended(for: mistyped) == target
                    ))
                }
            }
        }
        return result.sorted {
            ($0.isActive ? 0 : 1, -$0.count, $0.key, $0.value) < ($1.isActive ? 0 : 1, -$1.count, $1.key, $1.value)
        }
    }

    public func remove(_ entry: LearnedEntry) {
        switch entry.kind {
        case .phrase: phrases.remove(reading: entry.key, text: entry.value)
        case .history: history.remove(context: entry.key, next: entry.value)
        case .typo: typos.remove(mistyped: entry.key, intended: entry.value)
        }
    }
}
