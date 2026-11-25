import Foundation
import Testing
@testable import WolfEngine

private let lexicon = try! Lexicon(contentsOf: URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Data/mcbopomofo/data.txt"))

/// 使用者習慣把聲調鍵按到隔壁（想按 4 按成 5）：看過幾次之後，這種錯自動修正。
@Test func toneKeyNextToIntendedIsCorrectedOnlyForUsersWithTheHabit() {
    #expect(UserTypos.kind(Array("cl5"), Array("cl4")) == .toneNeighbor)
    #expect(UserTypos.kind(Array("cl8"), Array("cl4")) == nil)      // 8 不在 4 隔壁
    #expect(UserTypos.kind(Array("cp4"), Array("cl4")) == nil)      // 不是聲調鍵
    var plain = Segmenter(lexicon: lexicon)
    let intended = plain.layout("cl4su3").text
    #expect(plain.layout("cl5su3").text != intended)
    plain.typos = UserTypos(corrections: ["ho5": ["ho4": 3]])
    #expect(plain.typos?.habits.contains(.toneNeighbor) == true)
    #expect(plain.layout("cl5su3").text == intended)
    // 沒有這個習慣的人：不修。
    var other = Segmenter(lexicon: lexicon)
    other.typos = UserTypos(corrections: [:])
    #expect(other.layout("cl5su3").text != intended)
}

/// 常誤觸的鍵（數字、空白）：同一個鍵多按更正兩次以上才算；一次不算，免得把真的數字拿掉。
@Test func strayKeysNeedRepeatedCorrections() {
    #expect(UserTypos(corrections: ["1rup4": ["rup4": 1]]).strayKeys.isEmpty)
    #expect(UserTypos(corrections: ["1rup4": ["rup4": 2]]).strayKeys == ["1"])
    #expect(UserTypos(corrections: ["1rup4": ["rup4": 1], "1cl3": ["cl3": 1]]).strayKeys == ["1"])
    // 順序顛倒、漏按不算多按。
    #expect(UserTypos(corrections: ["ru4p": ["rup4": 5], "rp4": ["rup4": 5]]).strayKeys.isEmpty)
    // 常誤觸的數字鍵在選字窗裡能拿掉：1rup4 → rup4 的字。
    var seg = Segmenter(lexicon: lexicon)
    seg.typos = UserTypos(corrections: ["1su3": ["su3": 2]])
    let wanted = seg.layout("su3").text
    #expect(seg.candidates("1su3").contains { $0.text == wanted })
}

/// 最後一個音節還沒打聲調：選字窗把各聲調的字一起列出來，選一個就補上聲調。
@Test func toneLessLastSyllableOffersEveryTone() {
    var composer = Composer(segmenter: Segmenter(lexicon: lexicon))
    for key in "ji3su" { _ = composer.handle(.character(key)) }
    let panel = composer.handle(.down)
    #expect(panel.candidates.contains("你"))      // ㄋㄧˇ
    #expect(panel.candidates.contains("泥") || panel.candidates.contains("呢"))  // 其他聲調
    let index = panel.candidates.firstIndex(of: "你")!
    #expect(index < 9)
    #expect(composer.handle(.character(Character("\(index + 1)"))).marked == "我你")
}

/// 有「聲調按到隔壁」習慣的人，打 email／網址的字母尾巴（.tw、.vue）不能被當成聲調改掉。
/// w 是 3 的隔壁鍵，tw 曾被改成 t3＝尺，連前面的 . 也變成「。」。字母鍵的修正只留在 ↓ 候選。
@Test func letterNeighborOfToneKeyDoesNotOverrideEnglish() {
    var seg = Segmenter(lexicon: lexicon)
    seg.typos = UserTypos(corrections: ["ho5": ["ho4": 3]])
    #expect(seg.typos?.habits.contains(.toneNeighbor) == true)
    for typed in ["james@foso.tw", "www.abc.tw", "app.vue", "web.de", "tw"] {
        #expect(seg.layout(typed).text == typed)
    }
    #expect(seg.candidates("tw").contains { $0.text == "尺" })
    // 數字列的隔壁鍵照樣自動修。
    #expect(seg.layout("cl5su3").text == Segmenter(lexicon: lexicon).layout("cl4su3").text)
}

/// 打完最後一個音節忘了聲調就按 Enter：補成最常用的聲調的字，不把注音符號送出去；自動修正關掉就照舊。
@Test func enterFillsMissingToneOfLastSyllable() {
    var composer = Composer(segmenter: Segmenter(lexicon: lexicon))
    for key in "ji3su" { _ = composer.handle(.character(key)) }
    #expect(composer.handle(.enter).commit == "我你")

    var off = Segmenter(lexicon: lexicon)
    off.weights.typoTolerance = false
    var plain = Composer(segmenter: off)
    for key in "ji3su" { _ = plain.handle(.character(key)) }
    #expect(plain.handle(.enter).commit == "我su")

    // 整串都有聲調、或是英文（go 不是打到一半的注音），Enter 不動它。
    var done = Composer(segmenter: Segmenter(lexicon: lexicon))
    for key in "ji3su3" { _ = done.handle(.character(key)) }
    #expect(done.handle(.enter).commit == "我你")
}

@Test func enterLeavesEnglishTailAlone() {
    var composer = Composer(segmenter: Segmenter(lexicon: lexicon))
    for key in "ji3go" { _ = composer.handle(.character(key)) }
    #expect(composer.handle(.enter).commit == "我go")
}
