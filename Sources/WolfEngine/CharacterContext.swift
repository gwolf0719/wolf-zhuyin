/// 前後字搭配：在同音字之間依上下文挑選。
///
/// 試過用公開語料（Common Voice 台灣華語句子，約 1.9 萬句）統計相鄰字，語料太小、雜訊太多，
/// 評測反而變差（他→她、是→事），所以改用少數普遍成立、不必靠語料的規則：
/// - 數字後面接量詞或單位（100「元」不是「員」、9「點」、5「個」）。
/// - 句子結尾、標點前面是語助詞（go「吧」不是「八」、好「嗎」）。
public struct CharacterContext: Sendable {
    /// 子句開頭（輸入開頭、標點後面）。
    public static let sentenceStart: Character = "^"
    /// 接在數字後面。
    public static let afterNumber: Character = "#"
    /// 接在英文字母後面。
    public static let afterLatin: Character = "a"
    /// 子句結尾（輸入結尾、標點前面）。
    public static let sentenceEnd: Character = "$"

    /// 常接在數字後面的量詞與單位。
    static let measureWords: Set<Character> = Set("元塊年月日號點分秒個次天週人歲度本張件位名隻台輛倍樓層公克斤里寸頁章節題場")
    /// 句尾語助詞。
    static let particles: Set<Character> = Set("吧嗎呢啊呀喔哦啦嘛囉耶")

    public var measureWordBonus = 1.5
    public var particleBonus = 1.0

    public init() {}

    /// `next` 接在 `previous` 後面的加分；0 表示沒有意見。
    public func score(_ previous: Character, _ next: Character) -> Double {
        if previous == Self.afterNumber, Self.measureWords.contains(next) { return measureWordBonus }
        if next == Self.sentenceEnd, Self.particles.contains(previous) { return particleBonus }
        return 0
    }
}
