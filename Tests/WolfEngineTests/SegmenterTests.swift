import Foundation
import Testing
@testable import WolfEngine

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private let segmenter = Segmenter(
    lexicon: try! Lexicon(contentsOf: repositoryRoot.appendingPathComponent("Data/mcbopomofo/data.txt"))
)

private func convert(_ keys: String) -> String {
    segmenter.segment(keys).map(\.text).joined()
}

@Test func dachenParsesSyllableInStandardOrder() {
    #expect(Dachen.syllable(in: Array("su3"), from: 0)?.reading == "ㄋㄧˇ")
    #expect(Dachen.syllable(in: Array("5j/ "), from: 0)?.reading == "ㄓㄨㄥ")
    #expect(Dachen.syllable(in: Array("su"), from: 0) == nil)
    #expect(Dachen.keys(forReading: "ㄓㄨㄥ-ㄨㄣˊ") == "5j/ jp6")
}

@Test(arguments: [
    ("su3cl3", "你好"),
    ("hello world", "hello world"),
    ("ji3m/4Mac283y4", "我用Mac打字"),
    ("rup wu0 ", "今天"),
    ("go6", "誰"),
    // 標點：句子裡有中文就全形，純英文或夾在英數字中間就半形。
    ("su3cl3,ji3g4James.", "你好，我是James。"),
    ("hello, world!", "hello, world!"),
    ("5k4g4gp6ak7?", "這是什麼？"),
    ("w8 gji [cl3]", "他說「好」"),
    ("vu,4vu,7su3!", "謝謝你！"),
    ("u.3hello.world", "有hello.world"),
    ("284e949.52u03", "大概9.5點"),
    ("f(x)2k7", "f(x)的"),
    ("w8 (James)", "他（James）"),
])
func convertsKeys(keys: String, expected: String) {
    #expect(convert(keys) == expected)
}

@Test func leadingPunctuationFollowsPrecedingText() {
    #expect(segmenter.segment("?", afterChinese: true).map(\.text) == ["？"])
    #expect(segmenter.segment("?", afterChinese: false).map(\.text) == ["?"])
}

/// 不變式：輸出的各段剛好不重疊地蓋滿所有按鍵。
@Test func segmentsCoverEveryKeyExactlyOnce() {
    var generator = SystemRandomNumberGenerator()
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789 ,./;-AZ")
    for _ in 0..<500 {
        let keys = String((0..<Int.random(in: 0...30, using: &generator)).map { _ in alphabet.randomElement(using: &generator)! })
        var next = 0
        for segment in segmenter.segment(keys) {
            #expect(segment.keys.lowerBound == next, "按鍵「\(keys)」")
            next = segment.keys.upperBound
        }
        #expect(next == keys.count, "按鍵「\(keys)」")
    }
}

/// 不變式：詞庫裡的常見中文詞單獨輸入時，不可以被判成英文。
@Test func commonChineseWordsStayChinese() {
    let evaluation = Evaluation(segmenter: segmenter)
    var wrong: [String] = []
    var total = 0
    for entries in segmenter.lexicon.entries.values {
        guard let entry = entries.first, entry.score > -5 else { continue }
        guard let outcome = evaluation.run(entry.text) else { continue }
        total += 1
        // 「. 」「, 」「; 」刻意解讀成標點加空白，不是歐、欸、骯（要打這幾個字靠詞或選字窗）。
        if [". ", ", ", "; "].contains(outcome.keys) { continue }
        if !outcome.languageCorrect { wrong.append("\(entry.text)(\(outcome.keys))→\(outcome.actual)") }
    }
    #expect(total > 5000)
    #expect(wrong.isEmpty, "\(wrong.count)/\(total)：\(wrong.prefix(30))")
}

/// 評測集的中英判斷正確率不可以退步。門檻隨實測結果往上調。
@Test(arguments: [("Eval/dev.txt", 0.98), ("Eval/test.txt", 0.96)])
func languageAccuracyDoesNotRegress(path: String, threshold: Double) throws {
    let evaluation = Evaluation(segmenter: segmenter)
    let content = try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    let outcomes = content.split(separator: "\n").filter { !$0.hasPrefix("#") }.compactMap { evaluation.run(String($0)) }
    let accuracy = Double(outcomes.filter(\.languageCorrect).count) / Double(outcomes.count)
    #expect(accuracy >= threshold)
}

@Test func candidatesListLongerWordsFirstThenSingleCharacters() {
    let candidates = segmenter.candidates("vu,4vu,7")
    #expect(candidates.first?.text == "謝謝")
    #expect(candidates.first?.start == 0)
    // 單字候選只取代最後一個音節。
    #expect(candidates.contains { $0.start == 4 })
    #expect(segmenter.candidates("hello").isEmpty)
}
