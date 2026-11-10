import Foundation
import Testing
@testable import WolfEngine

private let lexicon = try! Lexicon(contentsOf: URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Data/mcbopomofo/data.txt"))

private func type(_ keys: String, _ composer: inout Composer) -> Composer.Result {
    var last = Composer.Result(handled: false)
    for key in keys { last = composer.handle(.character(key)) }
    return last
}

@Test func preferencesRoundTripAndDefaults() {
    let defaults = UserDefaults(suiteName: "wolf-test-\(UUID().uuidString)")!
    #expect(Preferences(defaults: defaults) == Preferences())
    var changed = Preferences()
    changed.autoSpace = true
    changed.typoTolerance = false
    changed.learning = false
    changed.predictions = false
    changed.autoUpdate = false
    changed.save(to: defaults)
    #expect(Preferences(defaults: defaults) == changed)
    // 0.1.0 就有的鍵名：關閉自動更新寫成 AutoUpdateDisabled = true。
    #expect(defaults.bool(forKey: "AutoUpdateDisabled"))
}

@Test func autoSpaceSeparatesChineseAndLatin() {
    var preferences = Preferences()
    preferences.autoSpace = true
    var composer = preferences.composer(lexicon: lexicon, stores: nil)
    #expect(type("ji3m/4Mac283y4", &composer).marked == "我用 Mac 打字")
    _ = composer.handle(.escape)
    #expect(type("ji3m/4 Mac", &composer).marked == "我用 Mac")       // 已經有空白不重複補
    _ = composer.handle(.escape)
    #expect(type("u.33ek7", &composer).marked == "有 3 個")       // 數字也算
    _ = composer.handle(.escape)
    #expect(type("su3cl3,Mac", &composer).marked == "你好，Mac")      // 標點旁邊不補
    #expect(composer.handle(.enter).commit == "你好，Mac")

    // 游標移動與退格照常：空白不是一個可以停的位置。
    let typed = type("ji3m/4Mac", &composer)
    #expect(typed.marked == "我用 Mac")
    // 「我用 Mac」：英文一次一個字母，跨過空白直接到「用」後面。
    #expect(typed.cursor == 6)
    #expect(composer.handle(.left).cursor == 5)
    #expect(composer.handle(.left).cursor == 4)
    #expect(composer.handle(.left).cursor == 2)
    #expect(composer.handle(.backspace).marked == "我 Mac")
}

@Test func autoSpaceOffByDefault() {
    var composer = Preferences().composer(lexicon: lexicon, stores: nil)
    #expect(type("ji3m/4Mac283y4", &composer).marked == "我用Mac打字")
}

@Test func disablingLearningDetachesStores() {
    let stores = Preferences.Stores(phrases: UserPhrases(), history: UserHistory(), typos: UserTypos())
    var on = Preferences()
    #expect(on.segmenter(lexicon: lexicon, stores: stores).history != nil)
    on.learning = false
    let off = on.segmenter(lexicon: lexicon, stores: stores)
    #expect(off.history == nil && off.userPhrases == nil && off.typos == nil)
}

@Test func disablingPredictionsPassesTabThrough() {
    var preferences = Preferences()
    preferences.predictions = false
    var composer = preferences.composer(lexicon: lexicon, stores: nil)
    let typed = type("1j4cl3", &composer)
    #expect(typed.prediction == nil)
    #expect(composer.handle(.tab) == Composer.Result(handled: false, commit: "不好"))
}

@Test func disablingTypoToleranceKeepsKeysAsTyped() {
    var preferences = Preferences()
    preferences.typoTolerance = false
    var composer = preferences.composer(lexicon: lexicon, stores: nil)
    #expect(type("s3ucl3", &composer).marked == "s3u好")
}
