import Carbon
import Cocoa

// 端對端測試：開一個真的文字視窗，切到已安裝的狼注音，送出按鍵事件，檢查文字框裡的結果。
// 用法：WolfE2E <按鍵> <期望文字>　特殊鍵寫成 {enter} {down} 等
// 執行時視窗會短暫搶走焦點，結束後還原原本的輸入法。

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("用法：WolfE2E <按鍵> <期望文字>")
    exit(2)
}
/// 按鍵序列：一般字元照打，特殊鍵寫成 {enter} {down} {up} {left} {right} {esc} {delete}。
enum Stroke { case character(Character), special(Int) }
let specialKeys = ["enter": kVK_Return, "down": kVK_DownArrow, "up": kVK_UpArrow, "left": kVK_LeftArrow,
                   "right": kVK_RightArrow, "esc": kVK_Escape, "delete": kVK_Delete]
var keys: [Stroke] = []
var rest = Substring(arguments[1])
while let first = rest.first {
    if first == "{", let close = rest.firstIndex(of: "}"), let code = specialKeys[String(rest[rest.index(after: rest.startIndex)..<close])] {
        keys.append(.special(code))
        rest = rest[rest.index(after: close)...]
    } else {
        keys.append(.character(first))
        rest = rest.dropFirst()
    }
}
let expected = arguments[2]
// 系統實際給的識別碼會多一段 bundle 名稱（小麥注音也是這樣）。
let modeID = ProcessInfo.processInfo.environment["WOLF_E2E_SOURCE"] ?? "tw.foso.inputmethod.WolfZhuyin.WolfZhuyin.Zhuyin"

/// 結束碼 75：沒有測（使用者正在用電腦，或測試途中被打斷），不算通過也不算失敗。
let skipped: Int32 = 75

// 測試視窗會搶走鍵盤焦點。使用者正在打字或用滑鼠時不跑，等到閒置 3 秒；等不到就略過。
func idleSeconds() -> Double {
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
}
var waited = 0.0
while idleSeconds() < 3 {
    guard waited < 20 else {
        print("略過：使用者正在操作電腦，不搶焦點（按鍵「\(arguments[1])」未測）")
        exit(skipped)
    }
    Thread.sleep(forTimeInterval: 0.5)
    waited += 0.5
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let window = NSWindow(
    contentRect: NSRect(x: 200, y: 200, width: 480, height: 160),
    styleMask: [.titled], backing: .buffered, defer: false
)
window.title = "狼注音端對端測試"
let textView = NSTextView(frame: window.contentView!.bounds)
textView.font = .systemFont(ofSize: 24)
window.contentView!.addSubview(textView)
window.makeKeyAndOrderFront(nil)
window.makeFirstResponder(textView)
app.activate(ignoringOtherApps: true)

let originalSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()

// 測試途中使用者按了鍵或把焦點切走，結果就不可信。
var interrupted = false
NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
    interrupted = true
    return event
}
NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: nil) { _ in
    interrupted = true
}

func finish(_ message: String, code: Int32) -> Never {
    TISSelectInputSource(originalSource)
    if interrupted, code != 0 {
        print("略過：測試途中被使用者操作打斷（按鍵「\(arguments[1])」未測）")
        exit(skipped)
    }
    print(message)
    exit(code)
}

/// 美式鍵盤的字元 → 虛擬鍵碼。
let keyCodes: [Character: Int] = [
    "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
    "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
    "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
    "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
    "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
    "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    " ": kVK_Space, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash, ";": kVK_ANSI_Semicolon,
    "-": kVK_ANSI_Minus, "'": kVK_ANSI_Quote, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
]
/// 要按 Shift 的字元 → 對應的不按 Shift 的鍵。
let shifted: [Character: Character] = ["?": "/", "<": ",", ">": ".", ":": ";", "!": "1", "(": "9", ")": "0"]

/// 用真的鍵盤事件（CGEvent）包成 NSEvent 送進視窗；手工拼的 NSEvent 不會被轉給輸入法。
func send(character: Character? = nil, keyCode: UInt16 = 0) {
    var code = Int(keyCode)
    var flags: CGEventFlags = []
    if let character {
        let lowered = Character(character.lowercased())
        if let base = shifted[character] { code = keyCodes[base]!; flags = .maskShift }
        else if let found = keyCodes[lowered] { code = found; if character.isUppercase { flags = .maskShift } }
        else if character == "\\" { code = kVK_ANSI_Backslash }
        else { finish("失敗：測試程式不認得按鍵「\(character)」", code: 2) }
    }
    for keyDown in [true, false] {
        let cgEvent = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: CGKeyCode(code), keyDown: keyDown)!
        cgEvent.flags = flags
        app.sendEvent(NSEvent(cgEvent: cgEvent)!)
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
    let filter = [kTISPropertyInputSourceID as String: modeID] as CFDictionary
    guard let source = (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first else {
        finish("失敗：找不到已啟用的輸入方式 \(modeID)", code: 1)
    }
    let status = TISSelectInputSource(source)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        let current = textView.inputContext?.selectedKeyboardInputSource ?? "nil"
        guard status == noErr, current == modeID else {
            finish("失敗：切不到 \(modeID)（OSStatus \(status)，目前是 \(current)）", code: 1)
        }
        var delay = 0.0
        for key in keys {
            delay += 0.08
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                switch key {
                case .character(let character): send(character: character)
                case .special(let code): send(keyCode: UInt16(code))
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.5) {
            let actual = textView.string
            let marked = textView.hasMarkedText()
            if let capture = ProcessInfo.processInfo.environment["WOLF_E2E_SCREENSHOT"] {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                task.arguments = ["-x", capture]
                try? task.run()
                task.waitUntilExit()
            }
            if actual == expected {
                finish("通過：按鍵「\(arguments[1])」→「\(actual)」\(marked ? "（仍在組字）" : "")", code: 0)
            } else {
                finish("失敗：按鍵「\(arguments[1])」期望「\(expected)」，文字框得到「\(actual)」\(marked ? "（仍在組字）" : "")", code: 1)
            }
        }
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 20) { finish("失敗：逾時", code: 1) }
app.run()
