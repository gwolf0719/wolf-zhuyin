import Foundation

/// 英文詞表。原型階段用系統內建的 `/usr/share/dict/words`（沒有詞頻），
/// 再加一份手寫的常用字清單當高分層。之後要換成有詞頻的詞表。
public struct EnglishWords: Sendable {
    public enum Tier: Sendable { case common, dictionary }

    private let common: Set<String>
    private let dictionary: Set<String>

    public init(dictionaryURL: URL = URL(fileURLWithPath: "/usr/share/dict/words")) {
        common = Set(Self.commonWords.split(whereSeparator: \.isWhitespace).map(String.init))
        let content = (try? String(contentsOf: dictionaryURL, encoding: .utf8)) ?? ""
        // 系統詞表收了大量冷僻的一、二字母「單字」，只會製造誤判，所以只取 3 個字母以上。
        dictionary = Set(content.split(separator: "\n").lazy.filter { $0.count >= 3 }.map { $0.lowercased() })
    }

    public func tier(of word: String) -> Tier? {
        let lowered = word.lowercased()
        if common.contains(lowered) { return .common }
        if dictionary.contains(lowered) { return .dictionary }
        return nil
    }

    private static let commonWords = """
    a an as at be by do go he if in is it me my no of ok on or so to up us we am hi
    the and for are but not you all any can had her was one our out day get has him his how man new now
    old see two way who boy did its let put say she too use that with have this will your from they know
    want been good much some time very when come here just like long make many more only over such take
    than them well were what about after again could every first found great house large learn never
    other place right small sound spell still study their there these thing think three water where
    which world would write also back because before between both call change check code data each
    even file find fix give help high idea keep last left life line list look made mean meet most move
    need next open part plan play point read real run same send set show side start stop sure talk team
    tell test then turn type used user wait week work year yes yet app bug build commit push pull merge
    branch deploy server client email phone meeting project review update version feature design
    release issue error login logout password account online offline download upload link page site
    web api key token model prompt input output mode switch auto today tomorrow please thanks thank
    sorry hello done todo note demo free cool nice fine great best better bad big little lot off own
    under into down should must may might does doing going being having said says made maybe really
    people person thing things something anything nothing everything someone everyone
    """
}
