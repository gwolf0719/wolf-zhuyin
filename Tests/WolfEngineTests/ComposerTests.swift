import Foundation
import Testing
@testable import WolfEngine

/// 這個檔案測的是組字與預測的「操作流程」，所以打開所有預測來源；
/// 「只在有把握時才預測」的預設行為另外在 predictionsOnlyWhenConfident 測。
private let segmenter: Segmenter = {
    var segmenter = Segmenter(
        lexicon: try! Lexicon(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Data/mcbopomofo/data.txt"))
    )
    segmenter.predictsOnlyWhenConfident = false
    return segmenter
}()

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
    // Tab 直接套用第一個預測，並列出全部（反白的是已經套用的那個）。
    let opened = composer.handle(.tab)
    #expect(opened.handled && opened.cyclesWithTab)
    #expect(opened.marked == "不好意思" && opened.candidates.first == "意思" && opened.highlighted == 0)
    #expect(opened.candidates.count > 1)
    #expect(composer.handle(.enter).commit == "不好意思")

    // 再按 Tab 換成下一個；按到最後一個再按就回到第一個。↑ 換回上一個。
    for key in "1j4cl3" { last = composer.handle(.character(key)) }
    let list = composer.handle(.tab).candidates
    let second = composer.handle(.tab)
    #expect(second.marked == "不好" + list[1] && second.highlighted == 1)
    #expect(composer.handle(.up).marked == "不好" + list[0])
    for _ in 0..<list.count { last = composer.handle(.tab) }
    #expect(last.marked == "不好" + list[0])
    // 接著打字就是接受：數字鍵也是照常打字（2＝ㄉ），不是選第幾個。
    #expect(composer.handle(.character("2")).marked == "不好" + list[0] + "ㄉ")
    _ = composer.handle(.escape)
    // 套用後按退格：整個預測拿掉，回到原本的內容。
    for key in "1j4cl3" { last = composer.handle(.character(key)) }
    _ = composer.handle(.tab)
    #expect(composer.handle(.backspace).marked == "不好")
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
    #expect(opened.marked == "不好吃")
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
    let chosen = composer.handle(.tab)
    #expect(chosen.candidates.first == "意思")
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
    #expect(composer.handle(.tab).marked == "所以")
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

/// 外部來源（本機模型）的預測：前文相同才採用，接在自己的預測後面；前文一變就失效。
@Test func externalPredictionsAreMergedForMatchingContext() {
    var composer = Composer(segmenter: segmenter)
    _ = type("1j4cl3", composer: &composer)
    #expect(composer.predictionContext == "不好")
    // 前文不對的不採用。
    #expect(composer.offer(predictions: ["吃"], for: "你好") == nil)
    // 太長或空的丟掉。
    #expect(composer.offer(predictions: ["", String(repeating: "長", count: 13)], for: "不好") == nil)
    let offered = composer.offer(predictions: ["說", "意思"], for: "不好")
    #expect(offered?.prediction == "意思" && offered?.predictions.last == "說")
    let panel = composer.handle(.tab)
    #expect(panel.candidates.first == "意思" && panel.candidates.filter { $0 == "意思" }.count == 1)
    var cycled = panel
    for _ in 0..<panel.candidates.firstIndex(of: "說")! { cycled = composer.handle(.tab) }
    #expect(cycled.marked == "不好說")
    // 接受（→ 關掉清單）之後前文變了：舊的外部預測不再出現。
    _ = composer.handle(.right)
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

/// 照打的按鍵改回中文時，選字窗直接列出同音字，不必選了再開一次（使用者 2026-11-11：伴獸家家酒）。
@Test func numberCanBeSwitchedToAnyHomophone() {
    var composer = Composer(segmenter: segmenter)
    // 切成照打的 up␠ 之後再按 ↓：除了「因」，同音的「音」也直接列出來。
    for key in "up " { _ = composer.handle(.character(key)) }
    _ = composer.handle(.down)
    #expect(composer.handle(.character("8")).marked == "up ")
    let panel = composer.handle(.down)
    #expect(panel.candidates.contains("因") && panel.candidates.contains("音"), "\(panel.candidates)")
}

/// 全是數字鍵的字接在中文後面要轉成中文：前一個字的聲調和韻母剛好也是數字鍵時（片 qu04、寫 vu,3）不能誤當成「數字後面」
///（使用者 2026-11-12：影片吧變成影片 187；伴獸家家酒的伴變成 104）。
@Test func digitOnlySyllablesAfterChinese() {
    func run(_ keys: String) -> String {
        var composer = Composer(segmenter: segmenter)
        return type(keys, composer: &composer).marked
    }
    #expect(run("u/3qu04187") == "影片吧")
    #expect(run("w8 2k7u/3qu04187") == "他的影片吧")
    #expect(run("ji3ul4vu,3104g.4ru8 ru8 ru.3").hasSuffix("家家酒"))
    #expect(!run("ji3ul4vu,3104g.4ru8 ru8 ru.3").contains("104"))
    // 認得的英數字後面也一樣。
    #expect(run("mp4187") == "mp4吧")
    // 真正的數字不受影響。
    #expect(run("0936123456") == "0936123456")
    #expect(run("sha256") == "sha256")
    #expect(run("ji3u.3100m06") == "我有100元")
}

/// 預設只在夠有把握時才預測：詞庫的常見後續不主動提示；自己打過 3 次以上、而且佔那段前文一半以上的才提示
///（2026-11-12 量測：詞庫來源命中 11%、個人紀錄有把握的 75%）。
@Test func predictionsOnlyWhenConfident() {
    var strict = segmenter
    strict.predictsOnlyWhenConfident = true
    strict.history = UserHistory()
    var composer = Composer(segmenter: strict)
    // 詞庫知道「不好」後面常接「意思」，但沒有個人紀錄就不提示，Tab 也照常交還給 app。
    #expect(composer.handle(.character("1")).prediction == nil)
    for key in "j4cl3" { #expect(composer.handle(.character(key)).prediction == nil) }
    #expect(composer.handle(.tab).handled == false)
    // 打過兩次還不夠。
    for _ in 0..<2 { strict.history?.record(["不好", "吃"]) }
    composer = Composer(segmenter: strict)
    var last = Composer.Result(handled: true)
    for key in "1j4cl3" { last = composer.handle(.character(key)) }
    #expect(last.prediction == nil)
    // 第三次開始提示；展開後其他來源排在後面當選項。
    strict.history?.record(["不好", "吃"])
    composer = Composer(segmenter: strict)
    for key in "1j4cl3" { last = composer.handle(.character(key)) }
    #expect(last.prediction == "吃")
    let panel = composer.handle(.tab)
    #expect(panel.candidates.first == "吃" && panel.candidates.contains("意思"))
    _ = composer.handle(.escape)
    // 同一段前文後面接的東西很分散時不提示（佔比不到一半）。
    for next in ["看", "玩", "說", "用"] { for _ in 0..<2 { strict.history?.record(["不好", next]) } }
    composer = Composer(segmenter: strict)
    for key in "1j4cl3" { last = composer.handle(.character(key)) }
    #expect(last.prediction == nil)
}

/// 送出後緊接著可以把整段拉回組字區重改；按了別的鍵就不行（使用者 2026-11-12：打錯很難改）。
@Test func committedTextCanBeReopened() {
    var strict = segmenter
    strict.history = UserHistory()
    var composer = Composer(segmenter: strict)
    #expect(composer.reopenableText == nil)
    _ = type("ji3y94ru8 ", composer: &composer)
    #expect(composer.handle(.enter).commit == "我在家")
    #expect(composer.reopenableText == "我在家")
    let reopened = composer.reopen()
    #expect(reopened?.marked == "我在家")
    #expect(reopened?.cursor == 3)
    #expect(composer.reopenableText == nil)
    // 拉回來之後照常編輯：移到「在」後面改成「再」。
    _ = composer.handle(.left)
    let panel = composer.handle(.down)
    let index = panel.candidates.firstIndex(of: "再")!
    #expect(composer.handle(.character(Character("\(index + 1)"))).marked == "我再家")
    #expect(composer.handle(.enter).commit == "我再家")
    // 選過的字拉回來還能再選一次。
    _ = composer.reopen()
    _ = composer.handle(.left)
    #expect(composer.handle(.down).candidates.contains("在"))
    _ = composer.handle(.escape)
    #expect(composer.handle(.enter).commit == "我再家")
    // 原封不動再送出，不重複記進用詞紀錄。
    #expect(strict.history?.count(after: "我", next: "再") == 1)
    // 送出後按了別的鍵：不能再拉回來。
    _ = composer.handle(.character("j"))
    #expect(composer.reopenableText == nil)
    _ = composer.handle(.escape)
    // 句末標點自動送出的也可以拉回來。
    #expect(type("su3cl3?", composer: &composer).committed == "你好？")
    #expect(composer.reopenableText == "你好？")
    #expect(composer.reopen()?.marked == "你好？")
    _ = composer.handle(.escape)
    // 點了別處（外殼呼叫 forgetCommit）之後不行。
    _ = type("su3cl3", composer: &composer)
    _ = composer.handle(.enter)
    composer.forgetCommit()
    #expect(composer.reopenableText == nil)
}

/// 按 ↑ 直接跳到沒把握的字並開選字窗，不必一格一格移（使用者 2026-11-12：打錯很難改）。
@Test func upArrowJumpsToDoubtfulCharacter() {
    var composer = Composer(segmenter: segmenter)
    // 「在」有分數相近的同音字「再」；「喜歡」「咖啡」是詞，不算可疑。
    _ = type("ji3y94vu3cj0 d8 zo ", composer: &composer)
    let before = composer.handle(.left)
    _ = composer.handle(.right)
    #expect(before.marked == "我在喜歡咖啡")
    let jumped = composer.handle(.up)
    #expect(jumped.cursor == 2, "游標應該停在「在」後面：\(jumped.cursor)")
    #expect(jumped.candidates.contains("再"))
    // 選了之後這個字就不再可疑。
    let index = jumped.candidates.firstIndex(of: "再")!
    _ = composer.handle(.character(Character("\(index + 1)")))
    _ = composer.handle(.right)
    #expect(composer.handle(.up).cursor != 2)
    _ = composer.handle(.escape)
    // 沒在組字時 ↑ 交還給 app。
    var idle = Composer(segmenter: segmenter)
    #expect(idle.handle(.up).handled == false)
}

/// 沒認出來的按鍵按 ↓：除了強制轉成中文，也列出其他可能的打錯。
@Test func unrecognizedKeysOfferSeveralCorrections() {
    var composer = Composer(segmenter: segmenter)
    _ = type("uvp ", composer: &composer)
    let panel = composer.handle(.down)
    // 順序顛倒的 vup（心、新）之外，還有別種修正（少一鍵、按到隔壁）。
    #expect(panel.candidates.first == "心", "\(panel.candidates)")
    #expect(panel.candidates.contains("新"))

}

/// 使用者回報（2026-11-12）：「讓 codex 幫你」變成「codex1； 你」。
/// 他常在句首打「你」，句首的加分被空白和「1；」後面的位置拿去用，贏過打得正確的 1;␠（ㄅㄤ）。
@Test func sentenceStartHabitDoesNotBreakCorrectSyllables() {
    var learning = segmenter
    let history = UserHistory()
    for _ in 0..<16 { history.record(["你"]) }
    learning.history = history
    var composer = Composer(segmenter: learning)
    #expect(type("su3u.3b;4 codex 1; su3", composer: &composer).marked == "你有讓 codex 幫你")
    // 真正的句首（中文後面的標點之後）照樣用得到紀錄。
    #expect(history.count(after: UserHistory.sentenceStart, next: "你") == 16)
}

/// 注音符號不是詞：不記進用詞紀錄，舊紀錄裡的載入時丟掉。
@Test func historyIgnoresBopomofoSymbols() throws {
    let history = UserHistory()
    history.record(["ㄍ", "剛", "我"])
    #expect(history.count(after: "ㄍ", next: "剛") == 0)
    #expect(history.all.keys.allSatisfy { !UserHistory.hasBopomofo($0) })

    let url = FileManager.default.temporaryDirectory.appendingPathComponent("wolf-history-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try JSONEncoder().encode(["ㄍ": ["剛": 2], "我": ["ㄧˇ": 3, "們": 2]]).write(to: url)
    let loaded = UserHistory(fileURL: url)
    #expect(loaded.all == ["我": ["們": 2]])
}

/// 使用者回報（2026-11-12）：「是剛剛」的 e; 按反成 ;e，出來是「是；ㄍ剛」。
/// 詞庫收了單獨的注音符號（e␠ → ㄍ），但那不算打對；習慣顛倒順序的人要能被修正。
@Test func loneBopomofoSymbolCountsAsUnrecognized() {
    var learning = segmenter
    learning.typos = UserTypos(corrections: ["s3u": ["su3": 3], "l3c": ["cl3": 3]])
    #expect(learning.typos?.habits.contains(.reordered) == true)
    var composer = Composer(segmenter: learning)
    #expect(type("g4;e e; ji3", composer: &composer).marked == "是剛剛我")
}

/// 使用者提案（2026-11-12）：選一段文字後按 \ 跳出成對的標點，選一個就包起來。
@Test func selectedTextCanBeWrappedInPairedPunctuation() {
    var composer = Composer(segmenter: segmenter)
    // 選取的文字先進組字區（中英混合都照原樣，不重新轉換），候選是各種成對標點。
    let opened = composer.wrap("狼注音 v1")!
    #expect(opened.marked == "狼注音 v1" && opened.commit == nil)
    #expect(opened.candidates.prefix(3) == ["「狼注音 v1」", "『狼注音 v1』", "（狼注音 v1）"])
    // 按數字鍵選定：直接送出，不留在組字區。
    let chosen = composer.handle(.character("2"))
    #expect(chosen.commit == "『狼注音 v1』" && chosen.marked.isEmpty && chosen.candidates.isEmpty)

    // 取消：原文原樣送回去（app 已經用組字區取代了選取範圍，不能就這樣丟掉）。
    _ = composer.wrap("su3")
    #expect(composer.handle(.escape).commit == "su3")
    // 沒選就接著打字：原文送回去，後面照常組字。
    _ = composer.wrap("你好")
    let typed = composer.handle(.character("j"))
    #expect(typed.commit == "你好" && typed.marked == "ㄨ")
    _ = composer.handle(.escape)
    // 第二頁有程式用的半形成對符號。
    _ = composer.wrap("x")
    #expect(composer.handle(.right).candidates.first == "{x}")
    #expect(composer.handle(.enter).commit == "{x}")

    // 組字中、有換行、太長的都不包，讓按鍵照常處理。
    #expect(composer.wrap("a\nb") == nil)
    #expect(composer.wrap(String(repeating: "字", count: Composer.wrapLimit + 1)) == nil)
    _ = composer.handle(.character("j"))
    #expect(composer.wrap("你好") == nil)
}

/// 包起來的文字不是使用者剛打的，不記進用詞紀錄。
@Test func wrappedSelectionIsNotLearned() {
    var learning = segmenter
    let history = UserHistory()
    learning.history = history
    var composer = Composer(segmenter: learning)
    _ = composer.wrap("別人的文字")
    #expect(composer.handle(.character("1")).commit == "「別人的文字」")
    #expect(history.contextCount == 0)
}

/// 使用者回報（2026-11-12）：「ai自動推薦」變成「末動推薦」。ai 不在英文詞表，被當成沒認出來的鍵拿去修正。
@Test func aiIsAnEnglishWord() {
    var learning = segmenter
    // 有「多按一鍵」習慣的人：aiy4 會被修成 ai4（末）。
    learning.typos = UserTypos(corrections: ["su33": ["su3": 3], "cl33": ["cl3": 3]])
    var composer = Composer(segmenter: learning)
    #expect(type("aiy42j/4", composer: &composer).marked.hasSuffix("自動"))
    _ = composer.handle(.escape)
    // 「摸」不受影響：單獨打、成詞都還是中文（ai 只放在低分層）。
    #expect(type("ai ", composer: &composer).marked == "摸")
    _ = composer.handle(.escape)
    #expect(type("zj3ai ", composer: &composer).marked == "撫摸")
}

/// 提示要列出全部的預測；模型的結果陸續回來時只往後加，已經列出來的不換位置。
@Test func allPredictionsAreListedAndExternalOnesAppend() {
    var learning = segmenter
    learning.predictsOnlyWhenConfident = true
    let history = UserHistory()
    for _ in 0..<4 { history.record(["我", "想", "吃飯"]) }
    learning.history = history
    var composer = Composer(segmenter: learning)
    let local = type("ji3vu;3", composer: &composer)
    _ = local
    let context = composer.predictionContext!
    let before = composer.offer(predictions: [], for: context)
    #expect(before == nil)
    let first = composer.offer(predictions: ["睡覺"], for: context)!
    #expect(first.predictions == ["吃飯", "睡覺"] && first.prediction == "吃飯")
    let second = composer.offer(predictions: ["睡覺", "回家"], for: context)!
    #expect(second.predictions == ["吃飯", "睡覺", "回家"])
}

@Test func modelOutputKeepsOnlyUsableContinuations() {
    let known: (Character) -> Bool = { $0 != "会" }
    let output = "接續：好，適合出去走走\n開会\n今天天氣很不錯\n（1）這是編號\n很好\n好"
    #expect(ModelOutput.predictions(from: output, after: "今天天氣很", limit: 5, isKnown: known) == ["好", "不錯", "很好"])
}
