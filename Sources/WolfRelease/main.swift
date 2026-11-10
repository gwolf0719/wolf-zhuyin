import Foundation
import WolfUpdate

// 發版工具。私鑰放在版本庫之外：~/.config/wolf-zhuyin/release-signing-key（權限 600）。
//   WolfRelease keygen            產生金鑰（已存在就不覆蓋），印出公鑰
//   WolfRelease public-key        印出現有私鑰對應的公鑰
//   WolfRelease sign <檔案>       印出該檔案的簽章（base64）
//   WolfRelease verify <檔案> <簽章檔>   用程式內建的公鑰驗證

let keyURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/wolf-zhuyin/release-signing-key")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func privateKey() -> String {
    guard let key = try? String(contentsOf: keyURL, encoding: .utf8) else { fail("找不到私鑰 \(keyURL.path)，先執行 keygen") }
    return key
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "keygen":
    guard !FileManager.default.fileExists(atPath: keyURL.path) else { fail("私鑰已存在，不覆蓋：\(keyURL.path)") }
    let keys = Update.generateKeyPair()
    do {
        try FileManager.default.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: keyURL.path, contents: Data(keys.privateKey.utf8), attributes: [.posixPermissions: 0o600]) else {
            fail("寫不進 \(keyURL.path)")
        }
    } catch { fail("建立資料夾失敗：\(error.localizedDescription)") }
    print(keys.publicKey)
case "public-key":
    do { print(try Update.publicKey(forPrivateKey: privateKey())) } catch { fail("私鑰格式不對") }
case "sign" where arguments.count == 2:
    guard let data = FileManager.default.contents(atPath: arguments[1]) else { fail("讀不到 \(arguments[1])") }
    do { print(try Update.sign(data, privateKey: privateKey())) } catch { fail("簽章失敗：\(error.localizedDescription)") }
case "verify" where arguments.count == 3:
    guard let data = FileManager.default.contents(atPath: arguments[1]),
          let signature = FileManager.default.contents(atPath: arguments[2]) else { fail("讀不到檔案") }
    guard Update.isValidSignature(signature, for: data) else { fail("簽章不符") }
    print("簽章正確")
default:
    fail("用法：WolfRelease keygen | public-key | sign <檔案> | verify <檔案> <簽章檔>")
}
