import Carbon
import Cocoa
import InputMethodKit
import WolfEngine

// 打包後的用法：
//   WolfZhuyin --register   向系統登記這個輸入法（安裝後跑一次）
//   WolfZhuyin --enable     把它加入使用者的輸入方式（等同在系統設定手動加入）
//   WolfZhuyin --status     印出系統是否認得、是否已啟用
// 不帶參數時由系統啟動，作為輸入法伺服器常駐。

private func installedSource() -> TISInputSource? {
    let filter = [kTISPropertyBundleID as String: Bundle.main.bundleIdentifier ?? ""] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
    return sources?.first
}

switch CommandLine.arguments.dropFirst().first {
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
let sharedSegmenter: Segmenter = {
    var segmenter = Segmenter(lexicon: try! Lexicon(contentsOf: lexiconURL))
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    segmenter.userPhrases = UserPhrases(fileURL: support.appendingPathComponent("WolfZhuyin/user-phrases.json"))
    return segmenter
}()

let server = IMKServer(
    name: Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String,
    bundleIdentifier: Bundle.main.bundleIdentifier
)
debugLog("server started name=\(Bundle.main.infoDictionary?["InputMethodConnectionName"] ?? "nil") server=\(String(describing: server))")
NSApplication.shared.run()
