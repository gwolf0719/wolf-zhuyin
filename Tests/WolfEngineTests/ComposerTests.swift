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
    #expect(result == Composer.Result(handled: true, commit: "我用Mac打字", marked: ""))
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
    #expect(type("s3u", composer: &composer).marked == "你s3u")
    #expect(composer.handle(.backspace).marked == "你")
    // 打錯的那串後面還有正確的字：先刪字，再刪整串。
    #expect(type("s3ucl3", composer: &composer).marked == "你s3u好")
    #expect(composer.handle(.backspace).marked == "你s3u")
    #expect(composer.handle(.backspace).marked == "你")
    // 漏按聲調：刪掉後面的字就回到「打到一半的音節」，補上聲調即可，不必重打。
    #expect(type("sucl3", composer: &composer).marked == "你su好")
    #expect(composer.handle(.backspace).marked == "你ㄋㄧ")
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
    for key in [Composer.Key.character(" "), .enter, .backspace, .escape, .up, .down, .left, .right, .other] {
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
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789 ,./;-")
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
    #expect(type("?", composer: &composer).marked == "?")
    _ = composer.handle(.escape)
    _ = type("su3cl3", then: .enter, composer: &composer)
    #expect(type("?", composer: &composer).marked == "？")
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
    #expect(composer.handle(.character("4")).marked == "你好？")
    #expect(composer.handle(.enter).commit == "你好？")

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
    UserPhrases(fileURL: url).learn(reading: "ㄗㄞˋ", text: "再")
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
