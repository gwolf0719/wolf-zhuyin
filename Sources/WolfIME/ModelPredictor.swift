import Foundation
import WolfEngine
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 用 macOS 內建的本機模型（Apple Intelligence）續寫句子，補充預測。
/// 全部在這台電腦上執行，不連網；模型不可用（系統太舊、沒開 Apple Intelligence）時 `isAvailable` 是 false，什麼都不做。
enum ModelPredictor {
    /// 交給模型的前文最多這麼多字：夠它看懂句子，又不會拖慢回應。
    static let contextLength = 40
    static let maximumPredictions = 3

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// 接在 `text` 後面最可能的幾種寫法。在背景執行，結果回到主執行緒；失敗或沒有結果時給空陣列。
    static func predict(after text: String, completion: @escaping @MainActor ([String]) -> Void) {
        let context = String(text.suffix(contextLength))
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), isAvailable, !context.isEmpty {
            Task.detached(priority: .userInitiated) {
                let lines = await continuations(of: context)
                await completion(lines)
            }
            return
        }
        #endif
        Task { @MainActor in completion([]) }
    }

    #if canImport(FoundationModels)
    /// 模型預設會當成聊天來「回答」，所以用範例把它固定在「只輸出接在後面的字」。
    private static let instructions = "你是繁體中文（台灣用語）輸入法的自動完成功能，不是聊天助理。你不回答問題、不打招呼、不解釋，只輸出續寫的文字。"

    private static func prompt(for text: String) -> String {
        """
        任務：句子續寫。只輸出接在後面的文字，三種，一行一種。

        句子：今天天氣很
        好
        熱
        不錯

        句子：我等一下要去
        開會
        吃飯
        買東西

        句子：\(text)
        """
    }

    @available(macOS 26.0, *)
    private static func continuations(of text: String) async -> [String] {
        let session = LanguageModelSession(instructions: instructions)
        let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 40)
        guard let response = try? await session.respond(to: prompt(for: text), options: options) else { return [] }
        return ModelOutput.predictions(from: response.content, after: text, limit: maximumPredictions)
    }
    #endif
}
