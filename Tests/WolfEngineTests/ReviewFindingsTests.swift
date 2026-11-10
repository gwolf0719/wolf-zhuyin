import Foundation
import Testing
@testable import WolfEngine

// Codex 2026-11-10 引擎審查發現的問題，每個一個回歸測試。

private let lexicon = try! Lexicon(contentsOf: URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Data/mcbopomofo/data.txt"))

private func type(_ keys: String, _ composer: inout Composer) -> Composer.Result {
    var last = Composer.Result(handled: false)
    for key in keys { last = composer.handle(.character(key)) }
    return last
}

/// 審查 #3：個人容錯也不可以改掉緊接在英文字母後面的內容。
@Test func personalTypoRespectsEnglishBoundary() {
    var segmenter = Segmenter(lexicon: lexicon)
    let typos = UserTypos()
    typos.learn(mistyped: "s3u", intended: "su3")
    typos.learn(mistyped: "s3u", intended: "su3")
    segmenter.typos = typos
    #expect(segmenter.segment("s3u").map(\.text).joined() == "你")
    #expect(segmenter.segment("As3u").map(\.text).joined() == "As3u")
}

/// 審查 #4：游標移到中間時，退格與選字要用整段的音節邊界，不能只看游標前面那一截重新判斷。
@Test func middleEditingUsesFullContextBoundaries() {
    var composer = Composer(segmenter: Segmenter(lexicon: lexicon))
    #expect(type("sucl3", &composer).marked == "你好")
    #expect(composer.handle(.left).cursor == 1)
    #expect(composer.handle(.backspace).marked == "好")
    _ = composer.handle(.escape)

    #expect(type("sucl3", &composer).marked == "你好")
    _ = composer.handle(.left)
    let opened = composer.handle(.down)
    #expect(opened.candidates.contains("你"))
}

/// 審查 #5：接受英文的預測要補上詞間空白。
@Test func acceptingEnglishPredictionKeepsWordSpacing() {
    var segmenter = Segmenter(lexicon: lexicon)
    segmenter.history = UserHistory()
    var composer = Composer(segmenter: segmenter)
    for _ in 0..<2 {
        _ = type("hello world", &composer)
        _ = composer.handle(.enter)
    }
    #expect(type("hello", &composer).prediction == "world")
    _ = composer.handle(.tab)
    #expect(composer.handle(.tab).marked == "hello world")
    #expect(composer.handle(.enter).commit == "hello world")
}

/// 審查 #2：檔案損毀時不可以默默覆蓋，要先留備份。
@Test func corruptStoreIsBackedUpNotOverwritten() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wolf-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("history.json")
    try Data("{壞掉的 JSON".utf8).write(to: url)

    let history = UserHistory(fileURL: url)
    history.record(["你好", "世界"])
    history.flush()
    let backups = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.contains("corrupt") }
    #expect(backups.count == 1)
    #expect(try String(contentsOf: folder.appendingPathComponent(backups[0]), encoding: .utf8) == "{壞掉的 JSON")
}

/// 審查 #1：多個視窗同時寫入時，磁碟上最後留下的必須是最新的內容。
@Test func concurrentWritesKeepNewestOnDisk() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wolf-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("typos.json")
    let typos = UserTypos(fileURL: url)
    await withTaskGroup(of: Void.self) { group in
        for index in 0..<200 {
            group.addTask { typos.learn(mistyped: "k\(index % 20)", intended: "su3") }
        }
    }
    typos.flush()
    let reloaded = UserTypos(fileURL: url)
    for index in 0..<20 { #expect(reloaded.intended(for: "k\(index)") == "su3", "k\(index)") }
}

/// 審查 #6：紀錄要有上限，不能無限長大。
@Test func historyIsBounded() {
    let history = UserHistory()
    for index in 0..<(UserHistory.maximumContexts + 500) {
        history.record(["前\(index)", "後"])
    }
    #expect(history.contextCount <= UserHistory.maximumContexts)
}
