import Foundation
import Testing
@testable import WolfEngine

private let segmenter = Segmenter(
    lexicon: try! Lexicon(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Data/mcbopomofo/data.txt"))
)

/// 模擬逐鍵打字，回傳（送出的文字, 最後的組字區）。
private func type(_ keys: String, then last: Composer.Key? = nil, composer: inout Composer) -> (committed: String, marked: String, cursor: Int) {
    var committed = ""
    var marked = ""
    var cursor = 0
    for key in keys.map(Composer.Key.character) + (last.map { [$0] } ?? []) {
        let result = composer.handle(key)
        committed += result.commit ?? ""
        marked = result.marked
        cursor = result.cursor
    }
    return (committed, marked, cursor)
}

@Test func typingShowsConversionAndEnterCommits() {
    var composer = Composer(segmenter: segmenter)
    #expect(type("ji3m/4Mac283y4", composer: &composer).marked == "我用Mac打字")
    let result = composer.handle(.enter)
    #expect(result.handled && result.commit == "我用Mac打字" && result.marked.isEmpty && result.candidates.isEmpty)
}

@Test func backspaceRemovesOneUnitAndEscapeClears() {
    var composer = Composer(segmenter: segmenter)
    // 已完成的中文字：一次刪整個字。
    _ = type("su3cl3", composer: &composer)
    #expect(composer.handle(.backspace).marked == "你")
    // 打到一半的音節：一次刪一個注音符號。
    #expect(type("cl", composer: &composer).marked == "你ㄏㄠ")
    #expect(composer.handle(.backspace).marked == "你ㄏ")
    #expect(composer.handle(.backspace).marked == "你")
    // 注音打錯變成一串認不出來的按鍵：一次刪整串。
    #expect(type("q3w", composer: &composer).marked == "你q3w")
    #expect(composer.handle(.backspace).marked == "你")
    // 打錯的那串後面還有正確的字：先刪字，再刪整串。
    #expect(type("q3wcl3", composer: &composer).marked == "你q3w好")
    #expect(composer.handle(.backspace).marked == "你q3w")
    #expect(composer.handle(.backspace).marked == "你")
    // 自動修正要靠旁邊的字組成詞（s3u + cl3 → 你好）。刪掉「好」之後證據不足，s3u 變回原樣，再退格整串刪掉。
    #expect(type("s3ucl3", composer: &composer).marked == "你你好")
    #expect(composer.handle(.backspace).marked == "你s3u")
    #expect(composer.handle(.backspace).marked == "你")
    // 漏按聲調、後面又還沒打完：顯示成打到一半的音節，補上聲調即可。
    #expect(type("su", composer: &composer).marked == "你ㄋㄧ")
    #expect(type("3", composer: &composer).marked == "你你")
    _ = composer.handle(.escape)
    // 被判成英文、純字母的亂碼也整段刪（「新」打成 uvp 少按空白之前的樣子）。
    #expect(type("su3uvk", composer: &composer).marked == "你uvk")
    #expect(composer.handle(.backspace).marked == "你")
    // 英文字黏著落單的聲調（us3）：整段刪。
    #expect(type("us3", composer: &composer).marked == "你us3")
    #expect(composer.handle(.backspace).marked == "你")
    _ = composer.handle(.escape)
    // 真的英文字一次刪一個字母，刪到一半（hel）也是。
    #expect(type("hello", composer: &composer).marked == "hello")
    #expect(composer.handle(.backspace).marked == "hell")
    #expect(composer.handle(.backspace).marked == "hel")
    #expect(composer.handle(.backspace).marked == "he")
    _ = composer.handle(.escape)
    #expect(type("OpenAI", composer: &composer).marked == "OpenAI")
    #expect(composer.handle(.backspace).marked == "OpenA")
    _ = composer.handle(.escape)
    // 標點一次刪一個。
    #expect(type("cl3,", composer: &composer).marked == "好，")
    #expect(composer.handle(.backspace).marked == "好")
    _ = type("su3", composer: &composer)
    #expect(composer.handle(.escape) == Composer.Result(handled: true, commit: nil, marked: ""))
    #expect(composer.flush() == nil)
}

@Test func keysPassThroughWhenNotComposing() {
    var composer = Composer(segmenter: segmenter)
    for key in [Composer.Key.character(" "), .enter, .backspace, .escape, .up, .down, .left, .right, .tab, .other] {
        #expect(composer.handle(key) == Composer.Result(handled: false, commit: nil, marked: ""))
    }
}

@Test func otherKeyCommitsThenPassesThrough() {
    var composer = Composer(segmenter: segmenter)
    _ = type("hello ", composer: &composer)
    #expect(composer.handle(.other) == Composer.Result(handled: false, commit: "hello ", marked: ""))
}

/// 不變式：不管怎麼按，送出的文字加上組字區，等於把「還留著的按鍵」整段轉換的結果；Enter 後一定清空。
@Test func randomKeystrokesNeverLoseText() {
    var generator = SystemRandomNumberGenerator()
    // 不含句點：句末標點會自動送出，那個行為另有測試。
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789 ,/;-")
    for _ in 0..<300 {
        var composer = Composer(segmenter: segmenter)
        var buffer = ""
        for _ in 0..<Int.random(in: 1...25, using: &generator) {
            if Int.random(in: 0..<6, using: &generator) == 0 {
                let result = composer.handle(.backspace)
                #expect(result.handled == !buffer.isEmpty)
                if !buffer.isEmpty { buffer.removeLast(max(1, segmenter.backspaceLength(buffer))) }
            } else {
                let character = alphabet.randomElement(using: &generator)!
                let result = composer.handle(.character(character))
                if result.handled { buffer.append(character) }
                #expect(result.commit == nil)
            }
        }
        let expected = segmenter.segment(buffer, afterChinese: true).map(\.text).joined()
        #expect(composer.handle(.enter).commit == (buffer.isEmpty ? nil : expected))
        #expect(composer.flush() == nil)
    }
}

@Test func punctuationAfterCommitFollowsCommittedText() {
    var composer = Composer(segmenter: segmenter)
    _ = type("hello", then: .enter, composer: &composer)
    #expect(type(",", composer: &composer).marked == ",")
    _ = composer.handle(.escape)
    _ = type("su3cl3", then: .enter, composer: &composer)
    #expect(type(",", composer: &composer).marked == "，")
}

/// 打到一半的音節在組字區顯示注音符號，但送出時是原本按的鍵。
@Test func pendingSyllableShowsBopomofoButCommitsKeys() {
    var composer = Composer(segmenter: segmenter)
    #expect(type("su", composer: &composer).marked == "ㄋㄧ")
    #expect(composer.handle(.enter).commit == "su")
    #expect(type("su3cl", composer: &composer).marked == "你ㄏㄠ")
    _ = composer.handle(.escape)
    // 英文字不會被拆成注音。
    #expect(type("abc", composer: &composer).marked == "abc")
    _ = composer.handle(.escape)
    #expect(type("hello", composer: &composer).marked == "hello")
    _ = composer.handle(.escape)
    // 中文後面單獨一個逗號是標點，不是ㄝ。
    #expect(type("cl3,", composer: &composer).marked == "好，")
}

@Test func downOpensCandidatesAndNumberSelects() {
    var composer = Composer(segmenter: segmenter)
    _ = type("ji3y94", composer: &composer)
    let opened = composer.handle(.down)
    #expect(opened.marked == "我在")
    #expect(opened.candidates.first == "我在" || opened.candidates.contains("在"))
    #expect(opened.candidates.contains("再"))
    let index = opened.candidates.firstIndex(of: "再")!
    // 選了之後留在組字區，Enter 才送出。
    let chosen = composer.handle(.character(Character("\(index + 1)")))
    #expect(chosen == Composer.Result(handled: true, marked: "我再"))
    #expect(composer.handle(.enter).commit == "我再")
    #expect(composer.flush() == nil)
}

@Test func candidatePanelNavigation() {
    var composer = Composer(segmenter: segmenter)
    _ = type("g4", composer: &composer)
    let first = composer.handle(.down)
    #expect(first.candidates.count == Composer.pageSize)
    #expect(first.highlighted == 0)
    #expect(composer.handle(.down).highlighted == 1)
    #expect(composer.handle(.up).highlighted == 0)
    let secondPage = composer.handle(.right)
    #expect(secondPage.candidates != first.candidates)
    #expect(composer.handle(.left).candidates == first.candidates)
    // Esc 只關選字窗，組字內容還在。
    let closed = composer.handle(.escape)
    #expect(closed.candidates.isEmpty)
    #expect(closed.marked == "是")
    // Enter 選反白的那個。
    _ = composer.handle(.down)
    _ = composer.handle(.down)
    #expect(composer.handle(.enter).marked == first.candidates[1])
    #expect(composer.handle(.enter).commit == first.candidates[1])
}

@Test func backslashOpensSymbolPanel() {
    var composer = Composer(segmenter: segmenter)
    _ = type("su3cl3", composer: &composer)
    let opened = composer.handle(.character("\\"))
    #expect(opened.candidates == Array(Composer.chineseSymbols.prefix(Composer.pageSize)))
    // 選到句末標點，整句直接送出。
    #expect(composer.handle(.character("4")) == Composer.Result(handled: true, commit: "你好？"))

    // 英文語境給半形符號。
    _ = type("hello", composer: &composer)
    #expect(composer.handle(.character("\\")).candidates == Array(Composer.englishSymbols.prefix(Composer.pageSize)))
    #expect(composer.handle(.character("1")).marked == "hello,")
    #expect(composer.handle(.enter).commit == "hello,")

    // 沒在組字時也能叫出來，依上一次送出的文字決定全半形。
    #expect(composer.handle(.character("\\")).candidates.first == ",")
    // 連按兩下輸出反斜線本身。
    #expect(composer.handle(.character("\\")).marked == "\\")
    #expect(composer.handle(.enter).commit == "\\")
}

@Test func typingWhilePanelOpenClosesItAndKeepsTyping() {
    var composer = Composer(segmenter: segmenter)
    _ = type("su3", composer: &composer)
    _ = composer.handle(.down)
    let result = type("cl3", composer: &composer)
    #expect(result.marked == "你好")
    #expect(composer.handle(.enter).commit == "你好")
}

/// 選字後要記住：同樣的前後文下次直接出選過的字，但不影響其他前後文。
@Test func chosenCandidateIsRememberedInSameContext() {
    var learning = segmenter
    learning.userPhrases = UserPhrases()
    var composer = Composer(segmenter: learning)

    _ = type("ji3y94", composer: &composer)
    let opened = composer.handle(.down)
    // 只改最後一個字：選單字「再」。
    let pageIndex = opened.candidates.lastIndex(of: "再")!
    #expect(composer.handle(.character(Character("\(pageIndex + 1)"))).marked == "我再")
    _ = composer.handle(.enter)

    #expect(type("ji3y94", composer: &composer).marked == "我再")
    _ = composer.handle(.escape)
    // 其他前後文與單獨打的「在」不受影響。
    #expect(type("w8 y94", composer: &composer).marked == "他在")
    _ = composer.handle(.escape)
    #expect(type("y94", composer: &composer).marked == "在")
    _ = composer.handle(.escape)
    // 再選回來也學得會，最近選的優先。
    _ = type("ji3y94", composer: &composer)
    let reopened = composer.handle(.down)
    #expect(reopened.candidates.first == "我再")
    let back = reopened.candidates.firstIndex(of: "我在")!
    _ = composer.handle(.character(Character("\(back + 1)")))
    _ = composer.handle(.enter)
    #expect(type("ji3y94", composer: &composer).marked == "我在")
}

@Test func learnedPhrasesPersistToDisk() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("wolf-test-\(UUID().uuidString)/user-phrases.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let first = UserPhrases(fileURL: url)
    first.learn(reading: "ㄗㄞˋ", text: "再")
    first.flush()
    #expect(UserPhrases(fileURL: url).texts(for: "ㄗㄞˋ") == ["再"])

    var learning = segmenter
    learning.userPhrases = UserPhrases(fileURL: url)
    #expect(learning.segment("y94").map(\.text) == ["再"])
    // 沒有設定使用者字詞的引擎不受影響。
    #expect(segmenter.segment("y94").map(\.text) == ["在"])
}

/// 修正中間的字：左右鍵移動游標（一次一個字），在游標處選字、刪除、插入。
@Test func editingInTheMiddleOfComposition() {
    var composer = Composer(segmenter: segmenter)
    // 我在家 → 把中間的「在」改成「再」
    let typed = type("ji3y94ru8 ", composer: &composer)
    #expect(typed.marked == "我在家")
    #expect(typed.cursor == 3)
    #expect(composer.handle(.left).cursor == 2)
    let opened = composer.handle(.down)
    let index = opened.candidates.lastIndex(of: "再")!
    let fixed = composer.handle(.character(Character("\(index + 1)")))
    #expect(fixed.marked == "我再家")
    #expect(fixed.cursor == 2)

    // 游標在中間時退格刪掉前一個字，打字插在游標處。
    #expect(composer.handle(.backspace).marked == "我家")
    let inserted = type("cl3", composer: &composer)
    #expect(inserted.marked == "我好家")
    #expect(inserted.cursor == 2)

    // 左右鍵不會超出範圍，也不會跳出組字區。
    for _ in 0..<5 { _ = composer.handle(.left) }
    #expect(composer.handle(.left) == Composer.Result(handled: true, marked: "我好家", cursor: 0))
    for _ in 0..<5 { _ = composer.handle(.right) }
    #expect(composer.handle(.right).cursor == 3)
    #expect(composer.handle(.enter).commit == "我好家")
}

@Test func cursorMovesByCharacterAcrossChineseAndEnglish() {
    var composer = Composer(segmenter: segmenter)
    _ = type("su3cl3Mac", composer: &composer)
    var positions: [Int] = []
    for _ in 0..<6 { positions.append(composer.handle(.left).cursor) }
    // 「你好Mac」：英文一次一個字母，中文一次一個字。
    #expect(positions == [4, 3, 2, 1, 0, 0])
    // 在開頭插入符號。
    _ = composer.handle(.character("\\"))
    let quote = Composer.chineseSymbols.firstIndex(of: "「")! + 1
    #expect(composer.handle(.character(Character("\(quote)"))).marked == "「你好Mac")
}

/// 不變式：游標永遠落在組字區文字的範圍內。
@Test func cursorAlwaysWithinMarkedText() {
    var generator = SystemRandomNumberGenerator()
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789 ,./;-")
    let actions: [Composer.Key] = [.left, .left, .right, .backspace, .down, .escape, .enter, .character("\\")]
    for _ in 0..<200 {
        var composer = Composer(segmenter: segmenter)
        for _ in 0..<40 {
            let key = Int.random(in: 0..<3, using: &generator) == 0
                ? actions.randomElement(using: &generator)!
                : Composer.Key.character(alphabet.randomElement(using: &generator)!)
            let result = composer.handle(key)
            #expect((0...result.marked.count).contains(result.cursor), "按鍵 \(key)")
        }
    }
}

/// 句末標點一出現就送出，不用按 Enter。
@Test func sentenceEndingPunctuationCommitsAutomatically() {
    var composer = Composer(segmenter: segmenter)
    // ? ! 沒有歧義，立刻送出。
    #expect(type("su3cl3", composer: &composer).marked == "你好")
    #expect(composer.handle(.character("?")) == Composer.Result(handled: true, commit: "你好？"))
    _ = type("cl3", composer: &composer)
    #expect(composer.handle(.character("!")).commit == "好！")
    // Shift+. 也立刻送出。
    _ = type("cl3", composer: &composer)
    #expect(composer.handle(.character(">")).commit == "好。")

    // . 也是韻母ㄡ：先顯示句號但不送，下一個鍵確定它是句號才送，後面的字留在組字區。
    let waiting = type("cl3.", composer: &composer)
    #expect(waiting.marked == "好。")
    #expect(waiting.committed == "")
    let next = composer.handle(.character("j"))
    #expect(next.commit == "好。")
    #expect(next.marked == "ㄨ")
    _ = composer.handle(.escape)
    // 結果是ㄡ開頭的字（偶）就不是句號，不送出。
    let ou = type("cl3.3", composer: &composer)
    #expect(ou.marked == "好偶")
    #expect(ou.committed == "")
    _ = composer.handle(.escape)

    // 逗號、頓號不送出；英文的句點、問號也不送出。
    #expect(type("cl3,", composer: &composer).committed == "")
    _ = composer.handle(.escape)
    let english = type("hello world. ok?", composer: &composer)
    #expect(english.committed == "")
    #expect(english.marked == "hello world. ok?")
}

@Test func tabAcceptsPredictionFromLexicon() {
    var composer = Composer(segmenter: segmenter)
    // 詞庫裡「不好」最常見的後續是「意思」。
    let typed = composer.handle(.character("1"))
    #expect(typed.prediction == nil)
    _ = composer.handle(.escape)
    var last = Composer.Result(handled: false)
    for key in "1j4cl3" { last = composer.handle(.character(key)) }
    #expect(last.marked == "不好")
    #expect(last.prediction == "意思")
    // Tab 列出所有預測；再按一次 Tab 選第一個。
    let opened = composer.handle(.tab)
    #expect(opened.handled)
    #expect(opened.candidates.first == "意思")
    #expect(opened.candidates.count > 1)
    #expect(composer.handle(.tab).marked == "不好意思")
    #expect(composer.handle(.enter).commit == "不好意思")

    // 數字鍵選其他的預測。
    for key in "1j4cl3" { last = composer.handle(.character(key)) }
    let list = composer.handle(.tab).candidates
    #expect(composer.handle(.character("2")).marked == "不好" + list[1])
    _ = composer.handle(.escape)
    // Esc 關掉預測清單，組字內容不變。
    for key in "1j4cl3" { last = composer.handle(.character(key)) }
    _ = composer.handle(.tab)
    let closed = composer.handle(.escape)
    #expect(closed.candidates.isEmpty)
    #expect(closed.marked == "不好")
}

@Test func tabPassesThroughWithoutPrediction() {
    var composer = Composer(segmenter: segmenter)
    // 英文、打到一半的音節都不預測；Tab 送出內容後交還給 app。
    #expect(type("hello", composer: &composer).marked == "hello")
    #expect(composer.handle(.tab) == Composer.Result(handled: false, commit: "hello"))
    for key in "su" { #expect(composer.handle(.character(key)).prediction == nil) }
    _ = composer.handle(.escape)
    // 游標不在結尾時不預測。
    for key in "1j4cl3" { _ = composer.handle(.character(key)) }
    #expect(composer.handle(.left).prediction == nil)
}

/// 自己打過的詞序優先於詞庫，而且只記在指定的地方。
@Test func predictionLearnsFromWhatWasTyped() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("wolf-test-\(UUID().uuidString)/history.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    var learning = segmenter
    learning.history = UserHistory(fileURL: url)
    var composer = Composer(segmenter: learning)

    // 打過兩次「不好吃」之後，「不好」後面推薦「吃」而不是詞庫的「意思」。
    for _ in 0..<2 {
        _ = type("1j4cl3t ", then: .enter, composer: &composer)
    }
    var last = Composer.Result(handled: false)
    for key in "1j4cl3" { last = composer.handle(.character(key)) }
    #expect(last.prediction == "吃")
    // 自己的用詞排第一，詞庫的排後面。
    let opened = composer.handle(.tab)
    #expect(opened.candidates.first == "吃")
    #expect(opened.candidates.contains("意思"))
    #expect(composer.handle(.tab).marked == "不好吃")
    _ = composer.handle(.escape)

    learning.history?.flush()
    // 重新載入後還在。
    #expect(UserHistory(fileURL: url).likely(after: ["不好"]).first == "吃")
    // 沒設定紀錄的引擎不受影響。
    var plain = Composer(segmenter: segmenter)
    for key in "1j4cl3" { last = plain.handle(.character(key)) }
    #expect(last.prediction == "意思")
}

@Test func historySplitsSentencesAtPunctuation() {
    #expect(segmenter.sentences("ji3m/4Mac283y4,hello world") == [["我", "用", "Mac", "打字"], ["hello", "world"]])
}

@Test func historyUsesTwoCharactersOfContextAndNeedsRepetition() {
    let history = UserHistory()
    history.record(["我", "用", "Mac", "打字"])
    // 只出現一次不預測。
    #expect(history.likely(after: ["我", "用", "Mac"]).isEmpty)
    history.record(["他", "用", "Mac", "打字"])
    #expect(history.likely(after: ["他", "用", "Mac"]) == ["打字"])
    // 中文用最後兩個字當前文：「我用」只出現一次，退到「用」出現兩次。
    #expect(history.likely(after: ["我", "用"]) == ["Mac"])
    #expect(history.likely(after: ["沒看過"]).isEmpty)
}

/// 游標正對著的字要標得出來：就是游標前面那一個單位。
@Test func focusFollowsTheCharacterBeforeCursor() {
    var composer = Composer(segmenter: segmenter)
    var last = Composer.Result(handled: false)
    for key in "ji3y94ru8 " { last = composer.handle(.character(key)) }
    #expect(last.marked == "我在家")
    #expect(last.focus == 2..<3)
    #expect(composer.handle(.left).focus == 1..<2)
    #expect(composer.handle(.left).focus == 0..<1)
    #expect(composer.handle(.left).focus.isEmpty)
    // 打到一半的音節整個是一個單位。
    _ = composer.handle(.escape)
    for key in "ji3su" { last = composer.handle(.character(key)) }
    #expect(last.marked == "我ㄋㄧ")
    #expect(last.focus == 1..<3)
}

/// 退格後重打成很像的東西＝一次更正。帶數字聲調的錯更正一次，之後就自動修，單獨一個字也修。
@Test func learnsPersonalTyposFromBackspaceAndRetype() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("wolf-test-\(UUID().uuidString)/typos.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    var learning = segmenter
    learning.typos = UserTypos(fileURL: url)
    var composer = Composer(segmenter: learning)

    // 通用規則不修單獨一個字的錯。
    #expect(type("s3u", composer: &composer).marked == "s3u")
    _ = composer.handle(.backspace)
    #expect(type("su3", composer: &composer).marked == "你")
    _ = composer.handle(.enter)
    // 更正過一次之後自動修正。
    #expect(type("s3u", composer: &composer).marked == "你")
    #expect(composer.handle(.enter).commit == "你")
    learning.typos?.flush()
    #expect(UserTypos(fileURL: url).intended(for: "s3u") == "su3")

    // 沒設定紀錄的引擎不受影響。
    var plain = Composer(segmenter: segmenter)
    #expect(type("s3u", composer: &plain).marked == "s3u")
}

/// 不該學的：換一個字（不是手誤）、原本就是正確音節、原本是英文字、中間做了別的事。
@Test func doesNotLearnFromChangesOfMind() {
    var learning = segmenter
    let typos = UserTypos()
    learning.typos = typos
    var composer = Composer(segmenter: learning)
    for _ in 0..<3 {
        // 好 → 壞：完全不同的字。
        _ = type("cl3", composer: &composer)
        _ = composer.handle(.backspace)
        _ = type("cj94", then: .enter, composer: &composer)
        // 膩（su4）→ 你（su3）：只差聲調，但 su4 本身是正確的音節，可能是真的想改字。
        _ = type("su4", composer: &composer)
        _ = composer.handle(.backspace)
        _ = type("su3", then: .enter, composer: &composer)
        // 中間移動過游標就不算。
        _ = type("s3u", composer: &composer)
        _ = composer.handle(.backspace)
        _ = composer.handle(.left)
        _ = type("su3", then: .enter, composer: &composer)
    }
    #expect(typos.intended(for: "cl3") == nil)
    #expect(typos.intended(for: "su4") == nil)
    #expect(typos.intended(for: "s3u") == nil)
}

@Test(arguments: [
    ("s3u", "su3", true), ("us3", "su3", true),   // 順序不同
    ("sy3", "su3", true),                           // 差一個鍵
    ("su", "su3", true), ("suu3", "su3", true),    // 少一個、多一個
    ("su3", "su3", false), ("cl3", "cj94", false), ("ab", "su3", false),
])
func typoSimilarity(mistyped: String, intended: String, expected: Bool) {
    #expect(UserTypos.looksLikeSameSyllable(Array(mistyped), Array(intended)) == expected)
}

/// 送出之後組字區是空的：緊接著按 Tab 可以接著打剛才那段的後續。
@Test func predictionContinuesAfterCommit() {
    var composer = Composer(segmenter: segmenter)
    _ = type("1j4cl3", composer: &composer)
    let committed = composer.handle(.enter)
    #expect(committed.commit == "不好")
    #expect(committed.prediction == "意思")
    let opened = composer.handle(.tab)
    #expect(opened.candidates.first == "意思")
    let chosen = composer.handle(.tab)
    #expect(chosen.marked == "意思")
    #expect(composer.handle(.enter).commit == "意思")
}

/// 送出後的預測只給緊接著的那一鍵；之後 Tab 照常交給 app，不會被吃掉。
@Test func predictionAfterCommitExpires() {
    var composer = Composer(segmenter: segmenter)
    _ = type("1j4cl3", then: .enter, composer: &composer)
    #expect(composer.handle(.left) == Composer.Result(handled: false))
    #expect(composer.handle(.tab) == Composer.Result(handled: false))

    // 點了別的地方（外殼呼叫 dismissPrediction）也一樣。
    _ = type("1j4cl3", then: .enter, composer: &composer)
    composer.dismissPrediction()
    #expect(composer.handle(.tab) == Composer.Result(handled: false))

    // 焦點離開時送出的內容不預測。
    _ = type("1j4cl3", composer: &composer)
    #expect(composer.flush() == "不好")
    #expect(composer.handle(.tab) == Composer.Result(handled: false))

    // 關掉預測就不提示、不攔。
    composer.predictionsEnabled = false
    let committed = type("1j4cl3", then: .enter, composer: &composer)
    #expect(committed.committed == "不好")
    #expect(composer.handle(.tab) == Composer.Result(handled: false))
}

/// 句末標點自動送出之後，預測下一句常用的開頭（來自自己的紀錄）。
@Test func predictionSuggestsSentenceOpening() {
    var learning = segmenter
    learning.history = UserHistory()
    var composer = Composer(segmenter: learning)
    // 打過兩句「所以…」開頭的話。
    for _ in 0..<2 { _ = type("nji3u3ji3m/4", then: .enter, composer: &composer) }
    #expect(learning.history?.likely(after: [UserHistory.sentenceStart]) == ["所以"])
    // 句號一出現就送出，接著提示下一句的開頭。
    var last = Composer.Result(handled: false)
    for key in "su3cl3?" { last = composer.handle(.character(key)) }
    #expect(last.commit == "你好？")
    #expect(last.prediction == "所以")
    _ = composer.handle(.tab)
    #expect(composer.handle(.character("1")).marked == "所以")
}

/// 英文送出後接英文預測，要補上詞間空白。
@Test func predictionAfterEnglishCommitAddsSpace() {
    var learning = segmenter
    learning.history = UserHistory()
    var composer = Composer(segmenter: learning)
    for _ in 0..<2 { _ = type("hello world", then: .enter, composer: &composer) }
    _ = type("hello", then: .enter, composer: &composer)
    _ = composer.handle(.tab)
    #expect(composer.handle(.tab).marked == " world")
}

/// 已經判定好的字可以手動切換：中文字切成照打的英文或注音符號，打到一半的音節選注音符號本身。
@Test func downArrowSwitchesLanguage() {
    var composer = Composer(segmenter: segmenter)
    _ = type("su3", composer: &composer)
    let panel = composer.handle(.down)
    // 第 8、9 個固定是「照打的英文」和「注音符號」。
    #expect(panel.candidates[7] == "su3")
    #expect(panel.candidates[8] == "ㄋㄧˇ")
    let english = composer.handle(.character("8"))
    #expect(english.marked == "su3")
    // 選定之後就固定，再打字也不會被改回中文。
    #expect(type("cl3", composer: &composer).marked == "su3好")
    #expect(composer.handle(.enter).commit == "su3好")

    _ = type("su3", composer: &composer)
    _ = composer.handle(.down)
    #expect(composer.handle(.character("9")).marked == "ㄋㄧˇ")
    #expect(composer.handle(.enter).commit == "ㄋㄧˇ")

    // 打到一半的音節：選注音符號本身。
    _ = type("ji3su", composer: &composer)
    let pending = composer.handle(.down)
    #expect(pending.candidates.contains("ㄋㄧ"))
    let index = pending.candidates.firstIndex(of: "ㄋㄧ")!
    #expect(composer.handle(.character(Character("\(index + 1)"))).marked == "我ㄋㄧ")

    // 被判成英文的：可以強制轉成中文。
    _ = composer.handle(.escape)
    _ = type("ji3m/4npm", composer: &composer)
    let forced = composer.handle(.down)
    #expect(forced.candidates.contains("ㄙㄣㄩ"))
}

/// 選過的字可以再改：再按 ↓ 照樣列出候選，也能切成英文、再切回中文。
@Test func chosenTextCanBeChangedAgain() {
    var composer = Composer(segmenter: segmenter)
    _ = type("y94", composer: &composer)
    var panel = composer.handle(.down)
    let first = panel.candidates[1]
    #expect(composer.handle(.character("2")).marked == first)
    // 第二次：游標還在這個字後面，↓ 照樣有候選。
    panel = composer.handle(.down)
    #expect(panel.candidates.contains("在"))
    #expect(composer.handle(.character(Character("\(panel.candidates.firstIndex(of: "在")! + 1)"))).marked == "在")

    // 兩個字的詞選過之後，也能只改其中一個字，或整個詞再換。
    _ = composer.handle(.escape)
    _ = type("vu,4vu,7", composer: &composer)
    _ = composer.handle(.down)
    #expect(composer.handle(.character("1")).marked == "謝謝")
    panel = composer.handle(.down)
    #expect(panel.candidates.first == "謝謝")

    // 切成英文之後，再按 ↓ 可以切回中文。（第一次 Esc 關選字窗，第二次清掉組字區）
    _ = composer.handle(.escape)
    _ = composer.handle(.escape)
    _ = type("su3", composer: &composer)
    _ = composer.handle(.down)
    #expect(composer.handle(.character("8")).marked == "su3")
    panel = composer.handle(.down)
    #expect(panel.candidates.contains("你"))
    #expect(composer.handle(.character(Character("\(panel.candidates.firstIndex(of: "你")! + 1)"))).marked == "你")
    // 強制轉回中文的字一樣可以再選。
    #expect(composer.handle(.down).candidates.contains("妳"))
}

/// 打對的字不自動改；按 ↓ 可以選「可能是打錯」的候選，選了會記成一次更正。
@Test func correctionsAreOfferedInPanel() {
    var learning = segmenter
    learning.typos = UserTypos()
    var composer = Composer(segmenter: learning)
    #expect(type("vu.3", composer: &composer).marked == "朽")
    let panel = composer.handle(.down)
    let index = panel.candidates.firstIndex(of: "有")
    #expect(index != nil && index! < 9)
    #expect(composer.handle(.character(Character("\(index! + 1)"))).marked == "有")
    #expect(learning.typos?.all["vu.3"] == ["u.3": 1])
}

/// 發版前審查找到的問題（2026-11-10，Codex 審查、Composer 重現）。
@Test func releaseReviewRegressions() {
    func run(_ keys: String, then extra: [Composer.Key] = []) -> (committed: String, marked: String) {
        var composer = Composer(segmenter: segmenter)
        var committed = ""
        var marked = ""
        for key in keys.map(Composer.Key.character) + extra {
            let result = composer.handle(key)
            committed += result.commit ?? ""
            marked = result.marked
        }
        return (committed, marked)
    }
    // 英數字後面的點不會被當成句號提前送出。
    #expect(run("ji3m/4app.json") == ("", "我用app.json"))
    #expect(run("ji3m/4v1.2").committed == "")
    // 中文後面的點照樣是句號、照樣自動送出。
    #expect(run("su3cl3.ji3").committed == "你好。")
    // 電話、編號不轉成中文。
    #expect(run("0936123456").marked == "0936123456")
    #expect(run("123456").marked == "123456")
    // 數字一次刪一位。
    #expect(run("1234", then: [.backspace]).marked == "123")
    // 一聲的字切成英文後能切回來。
    var composer = Composer(segmenter: segmenter)
    for key in "up " { _ = composer.handle(.character(key)) }
    _ = composer.handle(.down)
    #expect(composer.handle(.character("8")).marked == "up ")
    #expect(composer.handle(.down).candidates.contains("因"))
    // 多按一鍵跨到前面的數字：選字窗有「這」。
    composer = Composer(segmenter: segmenter)
    for key in "5ek4" { _ = composer.handle(.character(key)) }
    #expect(composer.handle(.down).candidates.contains("這"))
}

/// 中文句子裡的 [] 會變成「」；按 ↓ 可以改回半形的 []。
@Test func bracketsCanBeTypedAsIs() {
    var composer = Composer(segmenter: segmenter)
    #expect(type("ji3[]", composer: &composer).marked == "我「」")
    let panel = composer.handle(.down)
    let index = panel.candidates.firstIndex(of: "[]")
    #expect(index != nil)
    #expect(composer.handle(.character(Character("\(index! + 1)"))).marked == "我[]")
    #expect(composer.handle(.enter).commit == "我[]")
}

/// 中文裡用符號表打半形的 []：在第一頁，選了之後再打中文也不會變成「」。
@Test func symbolPanelTypesHalfWidthBrackets() {
    var composer = Composer(segmenter: segmenter)
    _ = type("ji3", composer: &composer)
    let panel = composer.handle(.character("\\"))
    let open = panel.candidates.firstIndex(of: "[")
    let close = panel.candidates.firstIndex(of: "]")
    #expect(open != nil && close != nil, "第一頁沒有 []：\(panel.candidates)")
    guard let open, let close else { return }
    #expect(composer.handle(.character(Character("\(open + 1)"))).marked == "我[")
    #expect(type("su3", composer: &composer).marked == "我[你")
    _ = composer.handle(.character("\\"))
    #expect(composer.handle(.character(Character("\(close + 1)"))).marked == "我[你]")
    #expect(type("cl3", composer: &composer).marked == "我[你]好")
    #expect(composer.handle(.enter).commit == "我[你]好")
}

/// 接在中文後面、整段只有英文時，括號仍是全形（使用者 2026-11-11：中文裡打 Mac』變成 Mac}）。
@Test func bracketsAroundEnglishStayFullWidthAfterChinese() {
    var composer = Composer(segmenter: segmenter)
    _ = type("ji3m/4", composer: &composer)
    #expect(composer.handle(.enter).commit == "我用")
    #expect(type("{Mac}", composer: &composer).marked == "『Mac』")
    #expect(composer.handle(.enter).commit == "『Mac』")
    // 左括號先送出了，後面只剩英文加右括號。
    _ = type("ji3m/4{", composer: &composer)
    #expect(composer.handle(.enter).commit == "我用『")
    #expect(type("Mac}", composer: &composer).marked == "Mac』")
    #expect(type("[app]", composer: &composer).marked == "Mac』「app」")
    _ = composer.handle(.enter)
    // 緊貼在英數字後面的左括號是程式寫法，維持半形。
    #expect(type("foo(1)", composer: &composer).marked == "foo(1)")
    _ = composer.handle(.escape)
    #expect(type("arr[0]", composer: &composer).marked == "arr[0]")
    _ = composer.handle(.escape)
    // 接在英文後面：照舊半形。
    _ = type("hello", composer: &composer)
    #expect(composer.handle(.enter).commit == "hello")
    #expect(type("{app}", composer: &composer).marked == "{app}")
}

/// 標點改成半形之後還能改回全形，再改成半形也行（使用者 2026-11-11：『 變成 { 後切不回來）。
@Test func punctuationCanBeSwitchedBackAndForth() {
    var composer = Composer(segmenter: segmenter)
    #expect(type("ji3{", composer: &composer).marked == "我『")
    for expected in ["我{", "我『", "我{", "我『"] {
        let target = String(expected.last!)
        let panel = composer.handle(.down)
        let index = panel.candidates.firstIndex(of: target)
        #expect(index != nil, "選字窗沒有 \(target)：\(panel.candidates)")
        guard let index else { return }
        #expect(composer.handle(.character(Character("\(index + 1)"))).marked == expected)
    }
    // 英文語境裡半形的括號也能改成全形。
    composer = Composer(segmenter: segmenter)
    #expect(type("hello[", composer: &composer).marked == "hello[")
    #expect(composer.handle(.down).candidates.contains("「"))
}

/// 外部來源（本機模型）的預測：前文相同才採用，排在自己的預測前面；前文一變就失效。
@Test func externalPredictionsAreMergedForMatchingContext() {
    var composer = Composer(segmenter: segmenter)
    _ = type("1j4cl3", composer: &composer)
    #expect(composer.predictionContext == "不好")
    // 前文不對的不採用。
    #expect(composer.offer(predictions: ["吃"], for: "你好") == nil)
    // 太長或空的丟掉。
    #expect(composer.offer(predictions: ["", String(repeating: "長", count: 13)], for: "不好") == nil)
    let offered = composer.offer(predictions: ["說", "意思"], for: "不好")
    #expect(offered?.prediction == "說")
    let panel = composer.handle(.tab)
    #expect(Array(panel.candidates.prefix(2)) == ["說", "意思"])
    #expect(panel.candidates.filter { $0 == "意思" }.count == 1)
    #expect(composer.handle(.tab).marked == "不好說")
    // 前文變了：舊的外部預測不再出現。
    #expect(composer.predictionContext == "不好說")
    #expect(!(composer.handle(.tab).candidates.contains("意思") && composer.predictionContext == "不好"))
    _ = composer.handle(.escape)
    _ = composer.handle(.escape)

    // 打到一半的音節、關掉預測時：沒有前文可問。
    _ = type("su", composer: &composer)
    #expect(composer.predictionContext == nil)
    _ = composer.handle(.escape)
    // 送出之後：前文是剛送出的文字。
    _ = type("su3cl3", then: .enter, composer: &composer)
    #expect(composer.predictionContext == "你好")
    #expect(composer.offer(predictions: ["嗎"], for: "你好")?.prediction == "嗎")
    composer.predictionsEnabled = false
    #expect(composer.predictionContext == nil)
}

/// 詞庫沒收的罕用字靠補充表打得出來，而且只排在同音字最後面，不影響平常的選字（使用者 2026-11-11：饍食光的「饍」）。
@Test func rareCharactersComeFromExtraTable() {
    var composer = Composer(segmenter: segmenter)
    #expect(type("g04", composer: &composer).marked == "善")
    var all: [String] = []
    var panel = composer.handle(.down)
    for _ in 0..<40 {
        all += panel.candidates
        let next = composer.handle(.right)
        if next.candidates == panel.candidates { break }
        panel = next
    }
    #expect(all.contains("饍"), "選字窗翻完沒有饍：\(all.count) 個")
    #expect(all.firstIndex(of: "膳")! < all.firstIndex(of: "饍") ?? .max)
}

/// 被當成數字的 104 想改成中文時，選字窗直接列出同音字，一次就能選到「伴」（使用者 2026-11-11：伴獸家家酒）。
@Test func numberCanBeSwitchedToAnyHomophone() {
    var composer = Composer(segmenter: segmenter)
    #expect(type("ji3ul4vu,3104", composer: &composer).marked == "我要寫104")
    let panel = composer.handle(.down)
    #expect(panel.candidates.first == "辦")
    let index = panel.candidates.firstIndex(of: "伴")
    #expect(index != nil, "第一頁沒有伴：\(panel.candidates)")
    guard let index else { return }
    #expect(composer.handle(.character(Character("\(index + 1)"))).marked == "我要寫伴")
    // 後面接著打，選好的字不會變。
    #expect(type("g.4ru8 ru8 ru.3", composer: &composer).marked == "我要寫伴受家家酒")
}
