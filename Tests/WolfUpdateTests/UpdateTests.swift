import Foundation
import Testing
@testable import WolfUpdate

@Test(arguments: [
    ("0.1.1", "0.1.0", true), ("v0.2.0", "0.1.9", true), ("0.10.0", "0.9.0", true), ("1.0", "0.9.9", true),
    ("0.1.0", "0.1.0", false), ("0.1", "0.1.0", false), ("0.0.9", "0.1.0", false),
    // 格式不對一律不更新。
    ("latest", "0.1.0", false), ("0.1.0-beta", "0.1.0", false), ("", "0.1.0", false), ("1.-1", "0.1.0", false), ("9.9.9", "dev", false),
])
func versionComparison(candidate: String, current: String, expected: Bool) {
    #expect(Update.isNewer(candidate, than: current) == expected)
}

/// 不變式：版本比對是嚴格順序——不會自己比自己新，也不會兩邊互相比對方新。
@Test func versionOrderIsStrict() {
    var generator = SystemRandomNumberGenerator()
    func random() -> String {
        (0..<Int.random(in: 1...4, using: &generator)).map { _ in String(Int.random(in: 0...12, using: &generator)) }.joined(separator: ".")
    }
    for _ in 0..<2000 {
        let a = random(), b = random()
        #expect(!Update.isNewer(a, than: a))
        #expect(!(Update.isNewer(a, than: b) && Update.isNewer(b, than: a)), "\(a) vs \(b)")
    }
}

@Test func signatureAcceptsOnlyUntamperedArchiveFromTheRightKey() throws {
    let keys = Update.generateKeyPair()
    let archive = Data("狼注音發版檔".utf8)
    let signature = Data(try Update.sign(archive, privateKey: keys.privateKey).utf8)
    #expect(Update.isValidSignature(signature, for: archive, publicKey: keys.publicKey))
    #expect(try Update.publicKey(forPrivateKey: keys.privateKey) == keys.publicKey)

    // 內容被改過、換了金鑰、簽章是垃圾：都必須拒絕。
    #expect(!Update.isValidSignature(signature, for: archive + Data([0]), publicKey: keys.publicKey))
    #expect(!Update.isValidSignature(signature, for: archive, publicKey: Update.generateKeyPair().publicKey))
    #expect(!Update.isValidSignature(Data("不是簽章".utf8), for: archive, publicKey: keys.publicKey))
    #expect(!Update.isValidSignature(Data(), for: archive, publicKey: keys.publicKey))
    #expect(!Update.isValidSignature(signature, for: archive, publicKey: "不是金鑰"))
}

/// 內建的公鑰必須是真的金鑰，不能是忘了換掉的佔位字串。
@Test func embeddedPublicKeyIsReal() {
    #expect(Data(base64Encoded: Update.publicKey)?.count == 32)
}

@Test func parsesReleaseAndRejectsForeignDownloadURLs() {
    func payload(tag: String, base: String) -> Data {
        Data("""
        {"tag_name": "\(tag)", "assets": [
          {"name": "WolfZhuyin.zip", "browser_download_url": "\(base)/WolfZhuyin.zip"},
          {"name": "WolfZhuyin.zip.sig", "browser_download_url": "\(base)/WolfZhuyin.zip.sig"}]}
        """.utf8)
    }
    let good = "https://github.com/gwolf0719/wolf-zhuyin/releases/download/v0.2.0"
    let release = Update.parseRelease(payload(tag: "v0.2.0", base: good))
    #expect(release?.version == "0.2.0")
    #expect(release?.archiveURL.absoluteString == good + "/WolfZhuyin.zip")

    #expect(Update.parseRelease(payload(tag: "v0.2.0", base: "https://evil.example/gwolf0719/wolf-zhuyin/releases/download/v0.2.0")) == nil)
    #expect(Update.parseRelease(payload(tag: "v0.2.0", base: "http://github.com/gwolf0719/wolf-zhuyin/releases/download/v0.2.0")) == nil)
    #expect(Update.parseRelease(payload(tag: "v0.2.0", base: "https://github.com/someone-else/wolf-zhuyin/releases/download/v0.2.0")) == nil)
    #expect(Update.parseRelease(payload(tag: "nightly", base: good)) == nil)
    #expect(Update.parseRelease(Data("{}".utf8)) == nil)
    #expect(Update.parseRelease(Data(#"{"tag_name": "v0.2.0", "assets": []}"#.utf8)) == nil)
}
