import Foundation
import WolfEngine
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 用 macOS 內建的本機模型（Apple Intelligence）續寫句子，補充預測。
/// 全部在這台電腦上執行，不連網；模型不可用（系統太舊、沒開 Apple Intelligence）時 `isAvailable` 是 false，什麼都不做。
///
/// 做法（2026-11-12 量過）：叫模型「一次列三種」時它常只給一種、照抄範例、或把一句話拆成三行；
/// 改成每次只要一種續寫、同時問幾次（一次取最可能的、其餘隨機取樣），十句測試句每句都能湊出 2–3 種合理的接法。
/// 第一個結果約 0.5–1 秒回來，其餘陸續補上。
enum ModelPredictor {
    /// 交給模型的前文最多這麼多字：夠它看懂句子，又不會拖慢回應。
    static let contextLength = 40
    static let maximumPredictions = 3
    /// 同時問幾次。隨機取樣常重複，所以比要的數量多問一次。
    private static let samples = 4

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// 接在 `text` 後面最可能的幾種寫法。在背景執行；每多一種就回主執行緒呼叫一次 `update`（給目前累積的全部，只增不減）。
    /// 回傳的工作可以取消（前文變了就不用再算）。
    @discardableResult
    static func predict(
        after text: String, isKnown: @escaping @Sendable (Character) -> Bool,
        update: @escaping @MainActor ([String]) -> Void
    ) -> Task<Void, Never>? {
        let context = String(text.suffix(contextLength))
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), isAvailable, !context.isEmpty {
            return Task.detached(priority: .userInitiated) {
                await withTaskGroup(of: String?.self) { group in
                    for index in 0..<samples {
                        group.addTask { await continuation(of: context, sample: index) }
                    }
                    var found: [String] = []
                    for await output in group {
                        guard let output, !Task.isCancelled else { continue }
                        let merged = ModelOutput.predictions(
                            from: (found + [output]).joined(separator: "\n"), after: context,
                            limit: maximumPredictions, isKnown: isKnown
                        )
                        guard merged.count > found.count else { continue }
                        found = merged
                        await update(found)
                        if found.count == maximumPredictions { group.cancelAll() }
                    }
                }
            }
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    /// 模型預設會當成聊天來「回答」，所以用範例把它固定在「只輸出接在後面的字」。
    private static let instructions = "你是繁體中文輸入法的自動完成，用台灣的用語（資料、軟體、影片，不說數據、軟件、視頻）。使用者打到一半，你只輸出緊接在後面的幾個字（2 到 8 個字），讓句子通順。不要重複前文、不要回答、不要解釋、不要標點。"

    private static func prompt(for text: String) -> String {
        """
        前文：今天天氣很
        接續：好，適合出去走走

        前文：我等一下要去
        接續：開會

        前文：這份報告麻煩你
        接續：幫我看一下

        前文：如果有問題的話
        接續：再跟我說

        前文：這個 bug 的原因是
        接續：資料沒有更新

        前文：\(text)
        接續：
        """
    }

    @available(macOS 26.0, *)
    private static func continuation(of text: String, sample: Int) async -> String? {
        let session = LanguageModelSession(instructions: instructions)
        // 第一次取最可能的；其餘隨機取樣，才會有不同的接法。
        let options = sample == 0
            ? GenerationOptions(sampling: .greedy, maximumResponseTokens: 12)
            : GenerationOptions(sampling: .random(top: 8, seed: UInt64(sample)), temperature: 0.9, maximumResponseTokens: 12)
        return try? await session.respond(to: prompt(for: text), options: options).content
    }
    #endif
}
