import Foundation

/// 整理本機模型的輸出。放在引擎裡是為了能用測試鎖住：模型偶爾會輸出編號、重複前文、自己編下一題、冒出簡體字。
public enum ModelOutput {
    /// 把模型的輸出整理成可以用的預測：一行一個，只留第一個標點之前的部分，去掉重複前文的、帶編號的、太長的。
    /// - Parameter isKnown: 這個中文字是不是輸入法認得的（詞庫有收）；有不認得的字（簡體、日文漢字）就整個不要。
    public static func predictions(
        from output: String, after text: String, limit: Int = 3, isKnown: (Character) -> Bool = { _ in true }
    ) -> [String] {
        var result: [String] = []
        for line in output.split(whereSeparator: \.isNewline) {
            var candidate = String(line).trimmingCharacters(in: .whitespaces)
            // 模型有時會自己接著編下一題。
            if candidate.hasPrefix("句子") || candidate.hasPrefix("前文") { break }
            if candidate.hasPrefix("接續：") { candidate = String(candidate.dropFirst(3)) }
            // 有時會把前文整句重寫一次。
            if candidate.hasPrefix(text) { candidate = String(candidate.dropFirst(text.count)) }
            // 只補到第一個標點之前（要不要斷句由使用者決定；標點後面多半是模型自己加的戲）。
            if let stop = candidate.firstIndex(where: { "。，！？、；：.!?,;:".contains($0) }) { candidate = String(candidate[..<stop]) }
            candidate = candidate.trimmingCharacters(in: .whitespaces)
            guard !candidate.isEmpty, candidate.count <= Composer.maximumExternalPredictionLength,
                  candidate.allSatisfy({ $0.isLetter || $0.isNumber || $0 == " " }),
                  candidate.contains(where: \.isLetter),  // 只有數字的是編號（1.）
                  candidate.allSatisfy({ $0.isASCII || isKnown($0) }),
                  !result.contains(candidate) else { continue }
            result.append(candidate)
            if result.count == limit { break }
        }
        return result
    }
}
