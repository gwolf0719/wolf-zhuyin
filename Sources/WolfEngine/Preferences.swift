import Foundation

/// 使用者可以在設定視窗切換的選項。存在輸入法自己的 UserDefaults。
public struct Preferences: Sendable, Equatable {
    /// 中文與英文、數字之間自動加一個空白（「我用 Mac 打字」）。
    public var autoSpace = false
    /// 注音打錯時自動修正。
    public var typoTolerance = true
    /// 記住選字、用詞與打錯習慣。關掉後不讀也不寫學習紀錄。
    public var learning = true
    /// 組字時提示接下來的字詞，按 Tab 選。
    public var predictions = true
    /// 每天自動檢查並安裝新版。
    public var autoUpdate = true

    public init() {}

    /// UserDefaults 的鍵。`AutoUpdateDisabled` 沿用 0.1.0 就有的鍵名，所以是反過來的意思。
    public enum Key {
        public static let autoSpace = "AutoSpace"
        public static let typoTolerance = "TypoTolerance"
        public static let learning = "Learning"
        public static let predictions = "Predictions"
        public static let autoUpdateDisabled = "AutoUpdateDisabled"
    }

    /// 設定改變時，設定視窗發出這個通知，外殼收到後重新套用。
    public static let didChangeNotification = Notification.Name("WolfZhuyinPreferencesDidChange")

    /// 讀取設定；沒存過的項目用預設值。
    public init(defaults: UserDefaults) {
        func read(_ key: String, default value: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
        }
        autoSpace = read(Key.autoSpace, default: false)
        typoTolerance = read(Key.typoTolerance, default: true)
        learning = read(Key.learning, default: true)
        predictions = read(Key.predictions, default: true)
        autoUpdate = !defaults.bool(forKey: Key.autoUpdateDisabled)
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(autoSpace, forKey: Key.autoSpace)
        defaults.set(typoTolerance, forKey: Key.typoTolerance)
        defaults.set(learning, forKey: Key.learning)
        defaults.set(predictions, forKey: Key.predictions)
        defaults.set(!autoUpdate, forKey: Key.autoUpdateDisabled)
    }

    /// 學習紀錄的三個存放處。外殼啟動時建立一次，之後依設定決定接不接上。
    public struct Stores: Sendable {
        public let phrases: UserPhrases
        public let history: UserHistory
        public let typos: UserTypos

        public init(phrases: UserPhrases, history: UserHistory, typos: UserTypos) {
            self.phrases = phrases
            self.history = history
            self.typos = typos
        }

        /// 放在 `~/Library/Application Support/WolfZhuyin/`。
        public static func inApplicationSupport() -> Stores {
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("WolfZhuyin")
            return Stores(
                phrases: UserPhrases(fileURL: folder.appendingPathComponent("user-phrases.json")),
                history: UserHistory(fileURL: folder.appendingPathComponent("history.json")),
                typos: UserTypos(fileURL: folder.appendingPathComponent("typos.json"))
            )
        }
    }

    /// 依設定組出引擎。
    public func segmenter(lexicon: Lexicon, stores: Stores?) -> Segmenter {
        var segmenter = Segmenter(lexicon: lexicon)
        segmenter.weights.typoTolerance = typoTolerance
        segmenter.autoSpace = autoSpace
        if learning, let stores {
            segmenter.userPhrases = stores.phrases
            segmenter.history = stores.history
            segmenter.typos = stores.typos
        }
        return segmenter
    }

    /// 依設定組出組字狀態機。
    public func composer(lexicon: Lexicon, stores: Stores?) -> Composer {
        var composer = Composer(segmenter: segmenter(lexicon: lexicon, stores: stores))
        composer.predictionsEnabled = predictions
        return composer
    }
}
