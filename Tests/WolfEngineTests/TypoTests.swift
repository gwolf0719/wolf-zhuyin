import Foundation
import Testing
@testable import WolfEngine

private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let segmenter = Segmenter(lexicon: try! Lexicon(contentsOf: root.appendingPathComponent("Data/mcbopomofo/data.txt")))
private let strict: Segmenter = {
    var copy = segmenter
    copy.weights.typoTolerance = false
    return copy
}()

private func text(_ keys: String, _ engine: Segmenter = segmenter) -> String {
    engine.segment(keys).map(\.text).joined()
}

private func lines(_ path: String) -> [String] {
    let content = try! String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    return content.split(separator: "\n").filter { !$0.hasPrefix("#") }.map(String.init)
}

@Test(arguments: [
    ("s3ucl3", "你好"),      // 聲調按太早
    ("us3cl3", "你好"),      // 前兩鍵顛倒
    ("sucl3", "你好"),       // 漏按聲調
    ("sy3cl3", "你好"),      // u 按成隔壁的 y
    ("ur8 g;4", "加上"),     // 空白當一聲、順序顛倒，夾著數字鍵 8
    ("tj/6uvp ", "重新"),    // 空白當一聲、全是字母的順序顛倒：要成詞才修
    ("ji3283nj04k27", "我打算的"), // 單字順序顛倒，夾著數字鍵 2：不必成詞也修
])
func recoversMistypedZhuyin(keys: String, expected: String) {
    #expect(text(keys) == expected)
}

/// 不變式：沒打錯的內容，開不開容錯結果都一樣。
@Test func toleranceDoesNotChangeCorrectInput() {
    let evaluation = Evaluation(segmenter: segmenter)
    for sentence in lines("Eval/dev.txt") + lines("Eval/test.txt") {
        guard let typed = evaluation.type(sentence) else { continue }
        #expect(text(typed.keys) == text(typed.keys, strict), "\(sentence)（\(typed.keys)）")
    }
}

/// 不變式：詞庫裡常見的中文詞照標準打法輸入時，開不開容錯結果都一樣。
@Test func toleranceDoesNotChangeCommonChineseWords() {
    let evaluation = Evaluation(segmenter: segmenter)
    var wrong: [String] = []
    var total = 0
    for entries in segmenter.lexicon.entries.values {
        guard let entry = entries.first, entry.score > -5.5, let typed = evaluation.type(entry.text) else { continue }
        total += 1
        if text(typed.keys) != text(typed.keys, strict) { wrong.append("\(entry.text)(\(typed.keys))→\(text(typed.keys))") }
    }
    #expect(total > 10000)
    #expect(wrong.isEmpty, "\(wrong.count)/\(total)：\(wrong.prefix(30))")
}

/// 不變式：英文字不可以被「修正」成中文——單獨打、接在中文後面、接在空白後面都一樣。
@Test func toleranceNeverRewritesEnglish() {
    let terms = lines("Eval/english-terms.txt").flatMap { $0.split(separator: " ").map(String.init) }
    let dictionary = try! String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8)
        .split(separator: "\n").filter { $0.count >= 3 && $0.allSatisfy { $0.isLowercase } }
    var sample = terms
    var index = 0
    while index < dictionary.count {
        sample.append(String(dictionary[index]))
        index += 97
    }
    var wrong: [String] = []
    for word in sample {
        for keys in [word, word + " ", "ji3m/4" + word, "ji3m/4 " + word, "hello " + word, word + "2k7"] {
            if text(keys) != text(keys, strict) { wrong.append("\(keys)→\(text(keys))") }
        }
    }
    #expect(sample.count > 2000)
    #expect(wrong.isEmpty, "\(wrong.count) 個：\(wrong.prefix(40))")
}

/// 量測：把評測集每個中文音節各弄錯一次，看有多少能還原成沒打錯時的結果。
/// 門檻隨實測結果調整，只准往上。
@Test func typoRecoveryRate() {
    let evaluation = Evaluation(segmenter: segmenter)
    var total = ["順序顛倒": 0, "漏按聲調": 0, "按到隔壁": 0]
    var recovered = total
    for sentence in lines("Eval/dev.txt") + lines("Eval/test.txt") {
        guard let typed = evaluation.type(sentence) else { continue }
        let keys = Array(typed.keys)
        let baseline = text(typed.keys, strict)
        var mutations: [(String, [Character])] = []
        for piece in strict.pieces(keys, afterChinese: true, showPending: false) where piece.reading != nil {
            var start = piece.keys.lowerBound
            for end in piece.syllableEnds {
                defer { start = end }
                guard end - start >= 2 else { continue }
                // 順序顛倒：音節內相鄰兩鍵互換。
                for position in start..<end - 1 where keys[position] != keys[position + 1] {
                    var mutated = keys
                    mutated.swapAt(position, position + 1)
                    mutations.append(("順序顛倒", mutated))
                }
                // 漏按聲調：後面還有字、而且這個音節至少兩個注音符號。
                if end < keys.count, end - start >= 3 {
                    var mutated = keys
                    mutated.remove(at: end - 1)
                    mutations.append(("漏按聲調", mutated))
                }
                // 按到隔壁：每個鍵換成每個相鄰鍵。
                for position in start..<end {
                    for neighbor in Dachen.neighbors[keys[position]] ?? [] {
                        var mutated = keys
                        mutated[position] = neighbor
                        mutations.append(("按到隔壁", mutated))
                    }
                }
            }
        }
        for (kind, mutated) in mutations {
            total[kind]! += 1
            if text(String(mutated)) == baseline { recovered[kind]! += 1 }
        }
    }
    for kind in total.keys.sorted() {
        let rate = Double(recovered[kind]!) / Double(max(total[kind]!, 1))
        print("打錯還原率 \(kind)：\(recovered[kind]!)/\(total[kind]!)（\(String(format: "%.1f", rate * 100))%）")
    }
    // 2026-11-10 改成「打得出正確注音的照打」之後，按到隔壁鍵多半剛好是另一個正確的音節，
    // 不再自動修（改由選字窗提供），所以這一項從 21% 降到 17%。這是刻意的取捨。
    for (kind, floor) in ["順序顛倒": 0.45, "漏按聲調": 0.38, "按到隔壁": 0.17] {
        #expect(Double(recovered[kind]!) / Double(total[kind]!) >= floor, "\(kind)")
    }
}

/// 夾數字的代號不可以被當成打錯的注音。
@Test(arguments: ["x86", "v3", "k8s", "e2e", "p2p", "h2o", "u2 ", "b2b ", "ok2 "])
func codesWithDigitsStayAsTyped(keys: String) {
    #expect(segmenter.segment(keys).map(\.text).joined() == keys)
}

/// 打錯的類型判斷。
@Test(arguments: [
    ("uv84", "vu84", UserTypos.Kind.reordered),
    ("urup4", "rup4", .extraKey),
    ("ho4", "hjo4", .missingKey),
])
func typoKindClassification(mistyped: String, intended: String, kind: UserTypos.Kind) {
    #expect(UserTypos.kind(Array(mistyped), Array(intended)) == kind)
}

/// 同一類打錯更正滿 3 次就成為習慣：沒看過的同類打錯，單字也直接修。
@Test func habitsGeneralizeToUnseenTypos() {
    var personal = segmenter
    // 還不是習慣：「ek7」順序顛倒、只有字母和聲調，單獨一個字要成詞才修，所以不修。
    personal.typos = UserTypos(corrections: ["uv84": ["vu84": 1], "ke6": ["ek6": 1]])
    #expect(personal.segment("ke7").map(\.text).joined() == "ke7")
    // 第三次順序顛倒的更正之後，成為習慣。
    personal.typos = UserTypos(corrections: ["uv84": ["vu84": 1], "ke6": ["ek6": 1], "ux;3": ["xu;3": 1]])
    #expect(personal.typos?.habits == [.reordered])
    #expect(personal.segment("ke7").map(\.text).joined() == "個")
    // 習慣多按一鍵：沒看過的 uru.4 也修成「就」。
    personal.typos = UserTypos(corrections: ["urup4": ["rup4": 2], "tr/6": ["t/6": 1]])
    #expect(personal.segment("uru.4").map(\.text).joined() == "就")
    // 習慣也不能改掉夾數字的代號。
    for code in ["x86", "v3", "k8s", "e2e", "h2o"] { #expect(personal.segment(code).map(\.text).joined() == code) }
}

/// 帶數字聲調的打錯更正一次就記住；空白當一聲的要兩次。
@Test func personalTypoThresholdDependsOnTone() {
    let typos = UserTypos(corrections: ["s3u": ["su3": 1], "ur, ": ["ru, ": 1]])
    #expect(typos.intended(for: "s3u") == "su3")
    #expect(typos.intended(for: "ur, ") == nil)
}

/// 一般規則：多按一鍵、漏按介音，修正後要能成詞。
@Test func extraKeyAndMissingMedialNeedAWord() {
    // 「進步」：rup4 多按一個 u。
    #expect(text("urup41j4") == "進步")
    // 「脆弱」：漏按 ㄨ。
    #expect(text("ho4bji4") == "脆弱")
}

/// 打得出正確注音的照打，不自動修正。修正改由選字窗提供。
/// 例外（使用者 2026-11-27 要求「有推薦就採用」）：聲調後面落單的韻母數字（我自9家 → 我在家），見下面的測試。
@Test func validInputIsNeverAutoCorrected() {
    #expect(text("vu.3") == "朽")
    #expect(text("vu,4vu7,") == "謝西，")  // 西＋逗號是正確的解讀
    #expect(text("ji32u/4xk75ek41u042; ") == "我定了5個便當")
    // 有使用者習慣時也一樣。
    var personal = segmenter
    personal.typos = UserTypos(corrections: [
        "vu.3": ["u.3": 3], "urup4": ["rup4": 3], "uv84": ["vu84": 3], "ho4": ["hjo4": 3],
    ])
    #expect(personal.typos?.habits == [.reordered, .extraKey, .missingKey])
    #expect(personal.segment("vu.3").map(\.text).joined() == "朽")
    #expect(personal.segment("ji32u/4xk75ek41u042; ").map(\.text).joined() == "我定了5個便當")
    // 選字窗裡有修正的候選。
    #expect(segmenter.candidates("vu.3").contains { $0.text == "有" })
}

/// 不變式：詞庫常用詞照標準按法打，套上各種打錯習慣後結果不變。
@Test func habitsNeverChangeCorrectInput() {
    var personal = segmenter
    personal.typos = UserTypos(corrections: ["uv84": ["vu84": 3], "urup4": ["rup4": 3], "ho4": ["hjo4": 3]])
    let evaluation = Evaluation(segmenter: segmenter)
    var wrong: [String] = []
    var index = 0
    for entries in segmenter.lexicon.entries.values {
        index += 1
        guard index % 7 == 0, let entry = entries.first, entry.score > -5.5, let typed = evaluation.type(entry.text) else { continue }
        if personal.segment(typed.keys).map(\.text).joined() != text(typed.keys) { wrong.append(typed.keys) }
    }
    #expect(wrong.isEmpty, "\(wrong.prefix(20))")
}


/// 聲調鍵按在最後一個韻母鍵前面（qu40 想打「片」）：結尾的直接換成更正的字詞（使用者 2026-11-26 要求），
/// 能成詞的（影片、我在）優先；照打的解讀（譬0、我自9）在選字窗第二個。
@Test(arguments: [("u/3qu40", "影片", "影譬0"), ("qu40", "片", "譬0"), ("vu48", "下", "系8"), ("ji3y49", "我在", "我自9")])
func trailingToneBeforeFinalIsSwapped(typed: String, expected: String, raw: String) {
    #expect(segmenter.segment(typed).map(\.text).joined() == expected)
    #expect(segmenter.segment(typed, showPending: true).map(\.text).joined() == expected)
    #expect(segmenter.candidates(typed).prefix(2).map(\.text) == [expected, raw])
}

/// 句中的也換（我自9家 → 我在家）；後面接數字或單位（是9點、共8個）、或是標點（是。）照打。
@Test func toneBeforeFinalInTheMiddle() {
    #expect(text("ji3y49ru8 ") == "我在家")
    #expect(text("u/3qu40ji3") == "影片我")
    #expect(text("g492u03") == "是9點")
    #expect(text("ej/48ek7") == "共8個")
    #expect(text("ji3g4.") == "我是。")
    #expect(text("vu,4vu7,") == "謝西，")
}

/// 有順序顛倒習慣時，整串都沒認出來的單字也採用推薦（jci4 → 或）；沒有習慣時要成詞才修。v3、x86 這類照打。
@Test func reorderedSingleCharacterIsCorrected() {
    var personal = segmenter
    personal.typos = UserTypos(corrections: ["ke6": ["ek6": 1], "ux;3": ["xu;3": 1], "uv84": ["vu84": 1]])
    #expect(personal.segment("jci4").map(\.text).joined() == "或")
    #expect(personal.segment("ji3jci4ji3").map(\.text).joined() == "我或我")
    #expect(personal.segment("url").map(\.text).joined() == "url")
    #expect(text("v3") == "v3")
    #expect(text("x86") == "x86")
    #expect(text("ji3m/4npm") == "我用npm")
}

/// 有順序顛倒、漏打聲調習慣的使用者（輸入法實際的狀況）：組字區也顯示更正後的字，不會顯示成「譬ㄢ」。
/// 2026-11-27 使用者回報「還是沒有優先採用推薦詞」：當時只用沒有學習紀錄的轉換器驗證，漏了這個。
@Test func toneBeforeFinalWithPersonalHabitsShowsCorrection() {
    var personal = segmenter
    personal.typos = UserTypos(corrections: [
        "ke6": ["ek6": 1], "ux;3": ["xu;3": 1], "jci4": ["cji4": 1], "ru,": ["ru, ": 1], "u5": ["u ": 2], "ru6,": ["ru,6": 1],
    ])
    for (typed, expected) in [("qu40", "片"), ("u/3qu40", "影片"), ("vu48", "下")] {
        #expect(personal.segment(typed, showPending: true).map(\.text).joined() == expected)
        #expect(personal.segment(typed).map(\.text).joined() == expected)
        #expect(personal.candidates(typed).first?.text == expected)
    }
    #expect(personal.candidates("qu40").prefix(2).map(\.text) == ["片", "譬0"])
    #expect(personal.segment("g492u03").map(\.text).joined() == "是9點")
}

/// 選回照打的解讀：譬0 就送出譬0。
@Test func choosingRawReadingAfterToneSwap() {
    var composer = Composer(segmenter: segmenter)
    for key in "qu40" { _ = composer.handle(.character(key)) }
    #expect(composer.handle(.down).candidates.prefix(2) == ["片", "譬0"])
    _ = composer.handle(.character("2"))
    #expect(composer.handle(.enter).commit == "譬0")
}

/// 選了之後整段換掉：「影譬0」選「影片」就是「影片」，不會留下 0。
@Test func choosingToneBeforeFinalCandidateReplacesTheDigit() {
    var composer = Composer(segmenter: segmenter)
    for key in "u/3qu40" { _ = composer.handle(.character(key)) }
    #expect(composer.handle(.down).candidates.first == "影片")
    _ = composer.handle(.character("1"))
    #expect(composer.handle(.enter).commit == "影片")
}
