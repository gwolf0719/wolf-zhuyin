import Foundation

/// 學習紀錄的存檔。三個紀錄（選字、用詞、打錯）共用，處理三件事：
/// 1. 寫入順序：所有寫入排進同一條序列佇列，執行時才向擁有者要「當下最新」的內容，
///    所以舊的快照不可能蓋掉新的（多個輸入視窗同時寫也一樣）。連續多次更新會合併成一次寫入。
/// 2. 讀取失敗：檔案存在但讀不到（權限、磁碟問題）時，這次執行期間完全不寫，避免用空資料蓋掉原檔。
/// 3. 檔案損毀：JSON 解不開時，先把原檔改名成 `*.corrupt-<時間>.json` 留著，再從空的開始。
final class JSONFile<Value: Codable>: @unchecked Sendable {
    private let url: URL?
    private let queue = DispatchQueue(label: "tw.foso.WolfZhuyin.store", qos: .utility)
    private let lock = NSLock()
    private var isScheduled = false
    private var isWritable = true

    init(url: URL?) {
        self.url = url
    }

    /// 讀取既有內容。檔案不存在、或損毀已備份時回傳 nil（從空的開始）。
    func load() -> Value? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else {
            isWritable = false
            return nil
        }
        if let value = try? JSONDecoder().decode(Value.self, from: data) { return value }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: url, to: backup)
        } catch {
            // 連備份都做不到，就不要碰原檔。
            isWritable = false
        }
        return nil
    }

    /// 排一次寫入。`snapshot` 在真正寫檔時才呼叫，要在擁有者的鎖裡回傳當下的內容。
    func save(_ snapshot: @escaping @Sendable () -> Value) {
        guard url != nil, isWritable else { return }
        let shouldSchedule: Bool = lock.withLock {
            defer { isScheduled = true }
            return !isScheduled
        }
        guard shouldSchedule else { return }
        queue.async { [self] in
            lock.withLock { isScheduled = false }
            write(snapshot())
        }
    }

    /// 等所有排定的寫入完成（測試與程式結束前用）。
    func flush() {
        queue.sync {}
    }

    private func write(_ value: Value) {
        guard let url, let data = try? JSONEncoder().encode(value) else { return }
        // 寫入失敗不影響打字；下次更新會再寫一次。
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
