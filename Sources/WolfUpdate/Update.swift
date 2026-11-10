import CryptoKit
import Foundation

/// 自動更新的純邏輯：版本比對、解析 GitHub 的版本資訊、驗證簽章。不做任何網路或檔案操作。
public enum Update {
    /// 發版簽章用的 Ed25519 公鑰（base64）。對應的私鑰只在發版的機器上，不進版本庫。
    public static let publicKey = "skWnnshaa8tjftlIr3xd7Hn7ueoucsMfC2X5MOapnDA="

    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/gwolf0719/wolf-zhuyin/releases/latest")!
    public static let archiveName = "WolfZhuyin.zip"
    public static let signatureName = "WolfZhuyin.zip.sig"

    public struct Release: Equatable, Sendable {
        public let version: String
        public let archiveURL: URL
        public let signatureURL: URL
    }

    /// 「1.2.10」這種以點分隔的數字版本；開頭的 v 會忽略。格式不對回傳 nil。
    static func components(of version: String) -> [Int]? {
        let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        return parts.map { $0! }
    }

    /// `candidate` 是否比 `current` 新。任何一邊格式不對都當作「不是」，寧可不更新。
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard var new = components(of: candidate), var old = components(of: current) else { return false }
        while new.count < old.count { new.append(0) }
        while old.count < new.count { old.append(0) }
        return new.lexicographicallyPrecedes(old) == false && new != old
    }

    /// 解析 GitHub「最新版本」API 的回應。只接受從同一個專案的發版頁下載的檔案。
    public static func parseRelease(_ data: Data) -> Release? {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let assets: [Asset]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              components(of: payload.tag_name) != nil else { return nil }
        func url(named name: String) -> URL? {
            payload.assets.first { $0.name == name }.map(\.browser_download_url).flatMap { url in
                url.scheme == "https" && url.host == "github.com"
                    && url.path.hasPrefix("/gwolf0719/wolf-zhuyin/releases/download/") ? url : nil
            }
        }
        guard let archive = url(named: archiveName), let signature = url(named: signatureName) else { return nil }
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        return Release(version: version, archiveURL: archive, signatureURL: signature)
    }

    /// 驗證下載的檔案確實由發版私鑰簽過。簽章檔內容是 base64。
    public static func isValidSignature(_ signature: Data, for archive: Data, publicKey: String = publicKey) -> Bool {
        guard let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let text = String(data: signature, encoding: .utf8),
              let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return key.isValidSignature(raw, for: archive)
    }

    /// 產生新的金鑰對（base64）。只給發版工具用。
    public static func generateKeyPair() -> (privateKey: String, publicKey: String) {
        let key = Curve25519.Signing.PrivateKey()
        return (key.rawRepresentation.base64EncodedString(), key.publicKey.rawRepresentation.base64EncodedString())
    }

    public static func sign(_ archive: Data, privateKey: String) throws -> String {
        guard let keyData = Data(base64Encoded: privateKey.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: keyData).signature(for: archive).base64EncodedString()
    }

    public static func publicKey(forPrivateKey privateKey: String) throws -> String {
        guard let keyData = Data(base64Encoded: privateKey.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: keyData).publicKey.rawRepresentation.base64EncodedString()
    }
}
