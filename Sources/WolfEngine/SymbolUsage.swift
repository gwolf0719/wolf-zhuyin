import Foundation

/// 符號表（\）各符號最近用了多少：越常用、越近用的排越前面。只存在本機。
/// 每用一次，所有舊紀錄先衰減一點，再給這個符號加一分，所以「最近」比「很久以前」重要。
public final class SymbolUsage: @unchecked Sendable {
    private let lock = NSLock()
    private var scores: [String: Double]
    private let file: JSONFile<[String: Double]>

    /// 每次選符號時，其他符號的分數乘上這個係數。
    static let decay = 0.97
    /// 分數低於這個就丟掉（太久沒用）。
    static let floor = 0.05

    public init(fileURL: URL? = nil) {
        file = JSONFile(url: fileURL)
        scores = file.load() ?? [:]
    }

    public func record(_ symbol: String) {
        lock.withLock {
            for key in scores.keys { scores[key] = scores[key]! * Self.decay }
            scores = scores.filter { $0.value >= Self.floor }
            scores[symbol, default: 0] += 1
        }
        file.save { [self] in lock.withLock { scores } }
    }

    /// 依用量重排。沒用過的符號保留預設順序，並給預設順序一點底分（最前面 2 分、最後面接近 0），
    /// 所以用過一次不會直接衝到最前面，連用幾次才會慢慢往前。
    public func sorted(_ symbols: [String]) -> [String] {
        let snapshot = lock.withLock { scores }
        let count = Double(symbols.count)
        let ranked = symbols.enumerated().map { index, symbol in
            (symbol, snapshot[symbol, default: 0] + 2 * (count - Double(index)) / count, index)
        }
        return ranked.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }.map(\.0)
    }

    public func flush() { file.flush() }
}
