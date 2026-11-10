import Foundation

/// 整理本機模型的輸出。放在引擎裡是為了能用測試鎖住：模型偶爾會輸出編號、重複前文、自己編下一題。
public enum ModelOutput {
    /// 把模型的輸出整理成可以用的預測：一行一個，去掉重複前文的、帶標點或編號的雜訊、太長的。
    public static func predictions(from output: String, after text: String, limit: Int = 3) -> [String] {
        var result: [String] = []
        for line in output.split(whereSeparator: \.isNewline) {
            var candidate = String(line).trimmingCharacters(in: .whitespaces)
            // 模型有時會自己接著編下一題。
            if candidate.hasPrefix("句子") { break }
            // 有時會把前文整句重寫一次。
            if candidate.hasPrefix(text) { candidate = String(candidate.dropFirst(text.count)) }
            // 句尾的標點不要（要不要結束句子由使用者決定）。
            while let last = candidate.last, "。，！？、.!?,".contains(last) { candidate.removeLast() }
            guard !candidate.isEmpty, candidate.count <= Composer.maximumExternalPredictionLength,
                  candidate.allSatisfy({ $0.isLetter || $0.isNumber || $0 == " " }),
                  candidate.contains(where: \.isLetter),  // 只有數字的是編號（1.）
                  !result.contains(candidate) else { continue }
            result.append(candidate)
            if result.count == limit { break }
        }
        return result
    }
}
