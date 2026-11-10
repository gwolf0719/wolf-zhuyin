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
    // 選字看上下文：數字後面是量詞、句尾是語助詞、完整的詞勝過拆開的單字。
    ("yj/3ej/4100m06", "總共100元"),
    ("ji3ap6go18 ", "我們go吧"),
    ("au/6wu0 y94gji ", "明天再說"),
    // 常用表裡夾數字的英文字（mp3）不會被當成注音。
    ("5k4g4mp32;304", "這是mp3檔案"),
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
        // mp3、mp4 刻意當英文：單獨打「允」「運」很少見，打 mp3、mp4 常見（要打這兩個字靠詞或選字窗）。
        if ["mp3", "mp4"].contains(outcome.keys) { continue }
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
    // 英文字沒有中文候選，只有切換用的注音符號。
    #expect(segmenter.candidates("hello").allSatisfy { $0.reading == nil })
}

/// 打字途中不可以把已經顯示的中文改回英文，或反過來。
@Test func typingDoesNotFlipEarlierText() {
    let evaluation = Evaluation(segmenter: segmenter)
    func steps(_ text: String) -> [String] { evaluation.stability(text)!.steps }
    // 「因」打出來之後，接著打下一個字的注音不會讓它變回 up。
    #expect(steps("因為他不在")[3] == "因ㄨ")
    // 開頭的 a、up 剛好是英文字：先顯示注音，不先顯示英文。
    #expect(steps("明天")[0...2] == ["ㄇ", "ㄇㄧ", "ㄇㄧㄥ"])
    #expect(steps("因為")[0...1] == ["ㄧ", "ㄧㄣ"])
    // 數字、大寫縮寫後面接中文：照樣顯示注音。
    #expect(steps("總共100元").contains("總共100ㄩㄢ"))
    #expect(steps("OK我知道了").contains("OKㄨㄛ"))
    // 英文字還沒打完時照字母顯示，不閃注音（hel 是 hello 的開頭）。
    #expect(steps("hello world").prefix(5) == ["ㄘ", "he", "hel", "hell", "hello"])
    #expect(steps("我用Mac打字").contains("我用Macㄉ"))
}

/// 評測集一鍵一鍵打，途中改判的句子不可以變多。門檻隨實測結果往下調。
@Test func typingStabilityDoesNotRegress() throws {
    let evaluation = Evaluation(segmenter: segmenter)
    var unstable = 0
    for path in ["Eval/dev.txt", "Eval/test.txt"] {
        let content = try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
        for line in content.split(separator: "\n") where !line.hasPrefix("#") {
            if let result = evaluation.stability(String(line)), !result.flips.isEmpty { unstable += 1 }
        }
    }
    #expect(unstable <= 4)
}

/// 同分的同音字（嗙／耪）每次都要選到同一個，否則組字區顯示的和送出的會不一樣。
@Test func tiedHomophonesAreChosenDeterministically() {
    let evaluation = Evaluation(segmenter: segmenter)
    for text in ["嗙", "耪"] {
        guard let keys = evaluation.type(text)?.keys else { continue }
        // 送出用的和組字區顯示用的（結尾顯示成注音）兩種轉換，第一個字要一樣。
        let first = segmenter.segment(keys + "v/f").map(\.text).joined().first
        for _ in 0..<20 {
            #expect(segmenter.segment(keys + "v/f").map(\.text).joined().first == first)
            #expect(segmenter.segment(keys + "v/f", showPending: true).map(\.text).joined().first == first)
        }
    }
}
