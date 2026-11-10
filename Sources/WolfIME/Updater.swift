import Cocoa
import WolfEngine
import WolfUpdate

/// 自動更新：向 GitHub 查最新版，下載後驗證簽章，通過才替換自己。
/// 關閉方式：defaults write tw.foso.inputmethod.WolfZhuyin AutoUpdateDisabled -bool true
enum Updater {
    static let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    /// 新版已經換到磁碟上，等不打擾使用者的時機重新啟動。
    nonisolated(unsafe) static var pendingRestart = false
    private static let maxDownloadBytes = 50 * 1024 * 1024

    /// 常駐時呼叫：啟動一分鐘後查一次，之後每天查一次。
    static func start() {
        func schedule(after seconds: TimeInterval) {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) {
                if Preferences(defaults: .standard).autoUpdate {
                    debugLog("更新檢查：\(checkAndInstall())")
                }
                // 關閉時保留排程，之後重新開啟選項就能在下一次恢復檢查。
                schedule(after: 24 * 60 * 60)
            }
        }
        schedule(after: 60)
    }

    /// 在不會打斷打字的時機呼叫（組字結束、輸入法被切走）。
    static func restartIfPending() {
        if pendingRestart { exit(0) }
    }

    private static func fetch(_ url: URL) -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("WolfZhuyin", forHTTPHeaderField: "User-Agent")
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200, let data, data.count <= maxDownloadBytes { result = data }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return result
    }

    /// 查詢並安裝新版，回傳給人看的結果。會阻塞，不要在主執行緒呼叫。
    static func checkAndInstall() -> String {
        guard let info = fetch(Update.latestReleaseURL) else { return "查不到版本資訊（沒有網路，或還沒有發版）" }
        guard let release = Update.parseRelease(info) else { return "版本資訊格式不符，略過" }
        guard Update.isNewer(release.version, than: currentVersion) else { return "已是最新版（\(currentVersion)）" }
        guard let archive = fetch(release.archiveURL), let signature = fetch(release.signatureURL) else { return "下載 \(release.version) 失敗" }
        guard Update.isValidSignature(signature, for: archive) else { return "\(release.version) 的簽章不符，拒絕更新" }

        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory.appendingPathComponent("WolfZhuyin-update-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: workspace) }
        do {
            try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
            let zip = workspace.appendingPathComponent(Update.archiveName)
            try archive.write(to: zip)
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", zip.path, workspace.path]
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else { return "解壓縮失敗" }

            // 簽章已經保證內容來自發版者；這裡再確認裡面確實是這個輸入法、版本也對得上。
            let newApp = workspace.appendingPathComponent("WolfZhuyin.app")
            guard let bundle = Bundle(url: newApp), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
                  bundle.infoDictionary?["CFBundleShortVersionString"] as? String == release.version else {
                return "下載的內容與版本資訊不符，拒絕更新"
            }
            _ = try fileManager.replaceItemAt(Bundle.main.bundleURL, withItemAt: newApp)
        } catch {
            return "安裝 \(release.version) 失敗：\(error.localizedDescription)"
        }
        pendingRestart = true
        return "已更新到 \(release.version)"
    }
}
