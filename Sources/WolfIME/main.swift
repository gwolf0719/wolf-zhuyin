import Carbon
import Cocoa
import InputMethodKit
import WolfEngine

// 打包後的用法：
//   WolfZhuyin --register   向系統登記這個輸入法（安裝後跑一次）
//   WolfZhuyin --enable     把它加入使用者的輸入方式（等同在系統設定手動加入）
//   WolfZhuyin --check-update  立刻檢查並安裝新版
//   WolfZhuyin --settings   開啟設定視窗，關閉後結束程式
//   WolfZhuyin --learned <資料夾>  用指定資料夾裡的紀錄開「學習紀錄」視窗（驗收畫面用；
//                           真正的紀錄只能從輸入法選單開，因為要和常駐的輸入法共用記憶體裡的那一份）
//   WolfZhuyin --version    印出版本
//   WolfZhuyin --predict <前文>  用本機模型預測接下來的內容，印出每個結果回來的時間（驗證與調提示詞用）
//   WolfZhuyin --status     印出系統是否認得、是否已啟用
// 不帶參數時由系統啟動，作為輸入法伺服器常駐。

private func installedSource() -> TISInputSource? {
    let filter = [kTISPropertyBundleID as String: Bundle.main.bundleIdentifier ?? ""] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
    return sources?.first
}

switch CommandLine.arguments.dropFirst().first {
case "--settings":
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    SettingsWindow.shared.terminatesOnClose = true
    SettingsWindow.shared.show()
    app.run()
    exit(0)

case "--learned":
    guard let path = CommandLine.arguments.dropFirst(2).first else {
        print("用法：WolfZhuyin --learned <資料夾>")
        exit(2)
    }
    let folder = URL(fileURLWithPath: path)
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let viewer = LearnedWindow(stores: Preferences.Stores(
        phrases: UserPhrases(fileURL: folder.appendingPathComponent("user-phrases.json")),
        history: UserHistory(fileURL: folder.appendingPathComponent("history.json")),
        typos: UserTypos(fileURL: folder.appendingPathComponent("typos.json"))
    ))
    viewer.terminatesOnClose = true
    LearnedWindow.shared = viewer
    viewer.show(kind: LearnedEntry.Kind(rawValue: Int(CommandLine.arguments.dropFirst(3).first ?? "0") ?? 0) ?? .phrase)
    app.run()
    exit(0)

case "--register":
    let status = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
    print(status == noErr ? "已登記" : "登記失敗（OSStatus \(status)）")
    exit(status == noErr ? 0 : 1)

case "--enable":
    // 等同在「系統設定 → 鍵盤 → 輸入方式」手動加入。由使用者自己執行。
    let filter = [kTISPropertyBundleID as String: Bundle.main.bundleIdentifier ?? ""] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
    guard !sources.isEmpty else {
        print("系統不認得這個輸入法，請先執行 --register")
        exit(1)
    }
    let failed = sources.map { TISEnableInputSource($0) }.filter { $0 != noErr }
    print(failed.isEmpty ? "已加入輸入方式" : "加入失敗（OSStatus \(failed[0])）")
    exit(failed.isEmpty ? 0 : 1)

case "--check-update":
    // 立刻檢查並安裝新版；常駐中的輸入法會被結束，下次切過去時啟動新版。
    let message = Updater.checkAndInstall()
    print(message)
    if Updater.pendingRestart {
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        where app.processIdentifier != me {
            app.terminate()
        }
    }
    exit(0)

case "--version":
    print(Updater.currentVersion)
    exit(0)

case "--predict":
    guard let text = CommandLine.arguments.dropFirst(2).first else {
        print("用法：WolfZhuyin --predict <前文>")
        exit(2)
    }
    guard ModelPredictor.isAvailable else {
        print("本機模型不可用（需要 macOS 26 並開啟 Apple Intelligence）")
        exit(1)
    }
    let lexicon = try! Lexicon(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("data.txt"))
    let started = Date()
    let task = ModelPredictor.predict(after: text, isKnown: { lexicon.contains($0) }) { predictions in
        print(String(format: "%.2f 秒", Date().timeIntervalSince(started)), predictions.joined(separator: "｜"))
    }
    Task {
        await task?.value
        print(String(format: "%.2f 秒 結束", Date().timeIntervalSince(started)))
        exit(0)
    }
    RunLoop.main.run()

case "--status":
    guard let source = installedSource() else {
        print("系統不認得這個輸入法")
        exit(1)
    }
    let enabled = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled)
        .map { Unmanaged<CFBoolean>.fromOpaque($0).takeUnretainedValue() == kCFBooleanTrue } ?? false
    print("系統認得這個輸入法，\(enabled ? "已啟用" : "尚未啟用")")
    exit(0)

default:
    break
}

let lexiconURL = Bundle.main.resourceURL!.appendingPathComponent("data.txt")
let sharedLexicon = try! Lexicon(contentsOf: lexiconURL)
let sharedStores = Preferences.Stores.inApplicationSupport()

let server = IMKServer(
    name: Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String,
    bundleIdentifier: Bundle.main.bundleIdentifier
)
Updater.start()
debugLog("server started name=\(Bundle.main.infoDictionary?["InputMethodConnectionName"] ?? "nil") server=\(String(describing: server))")
NSApplication.shared.run()
