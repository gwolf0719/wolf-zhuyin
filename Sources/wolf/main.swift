import Foundation
import WolfEngine

let usage = """
用法：
  wolf type <按鍵>      把按鍵序列轉成文字，例如 wolf type "su3cl3hello "
  wolf keys <文字>      把文字反推成按鍵序列
  wolf eval <檔案>...   跑評測集（每行一句期望輸出，# 開頭為註解）
詞庫路徑預設 Data/mcbopomofo/data.txt，可用環境變數 WOLF_LEXICON 覆蓋。
"""

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else {
    print(usage)
    exit(2)
}

let lexiconPath = ProcessInfo.processInfo.environment["WOLF_LEXICON"] ?? "Data/mcbopomofo/data.txt"
let segmenter: Segmenter
do {
    segmenter = Segmenter(lexicon: try Lexicon(contentsOf: URL(fileURLWithPath: lexiconPath)))
} catch {
    FileHandle.standardError.write(Data("讀不到詞庫 \(lexiconPath)：\(error.localizedDescription)\n".utf8))
    exit(1)
}
let evaluation = Evaluation(segmenter: segmenter)

switch arguments[0] {
case "type":
    let segments = segmenter.segment(arguments[1])
    print(segments.map(\.text).joined())
    print(segments.map { "[\($0.language == .chinese ? "中" : "英") \($0.text)]" }.joined(separator: " "))

case "keys":
    guard let typed = evaluation.type(arguments[1]) else {
        print("詞庫裡查不到其中某些字")
        exit(1)
    }
    print(typed.keys)

case "eval":
    var total = 0, languageCorrect = 0, textCorrect = 0, skipped = 0
    for path in arguments.dropFirst() {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            FileHandle.standardError.write(Data("讀不到 \(path)\n".utf8))
            exit(1)
        }
        for line in content.split(separator: "\n") where !line.hasPrefix("#") {
            guard let outcome = evaluation.run(String(line)) else {
                skipped += 1
                print("略過（詞庫查不到字）：\(line)")
                continue
            }
            total += 1
            if outcome.languageCorrect { languageCorrect += 1 }
            if outcome.textCorrect { textCorrect += 1 }
            if !outcome.languageCorrect {
                print("中英判錯：\(outcome.expected)\n    按鍵 \(outcome.keys)\n    得到 \(outcome.actual)")
            } else if !outcome.textCorrect {
                print("選字不同：\(outcome.expected)\n    得到 \(outcome.actual)")
            }
        }
    }
    func percent(_ count: Int) -> String { String(format: "%.1f%%", total == 0 ? 0 : Double(count) * 100 / Double(total)) }
    print("----")
    print("句數 \(total)，略過 \(skipped)")
    print("中英判斷全對 \(languageCorrect)/\(total)（\(percent(languageCorrect))）")
    print("文字完全相同 \(textCorrect)/\(total)（\(percent(textCorrect))）")

default:
    print(usage)
    exit(2)
}
