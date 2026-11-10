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
    // 英文字照一般習慣一次刪一個字母，詞表沒收的也是。
    #expect(type("hello", composer: &composer).marked == "hello")
    #expect(composer.handle(.backspace).marked == "hell")
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
    #expect(composer.handle(.character("8")).marked == "「你好Mac")
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

/// 退格後重打成很像的東西＝一次更正。同一個錯更正過兩次，之後就自動修，單獨一個字也修。
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
    // 只更正過一次，還不套用。
    #expect(type("s3u", composer: &composer).marked == "s3u")
    _ = composer.handle(.backspace)
    _ = type("su3", then: .enter, composer: &composer)
    // 第二次之後自動修正。
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
