import Foundation
import WolfEngine

let usage = """
用法：
  wolf type <按鍵>      把按鍵序列轉成文字，例如 wolf type "su3cl3hello "
  wolf keys <文字>      把文字反推成按鍵序列
  wolf eval <檔案>...   跑評測集（每行一句期望輸出，# 開頭為註解）
  wolf steps <文字>     一鍵一鍵打，印出每一步組字區的樣子
  wolf stability <檔案>... 列出打字途中中英被改判的句子
  wolf personal [-v]    用本機的學習紀錄評測（打錯還原率、常用詞組轉換）
詞庫路徑預設 Data/mcbopomofo/data.txt，可用環境變數 WOLF_LEXICON 覆蓋。
"""

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 || arguments.first == "personal" else {
    print(usage)
    exit(2)
}

let lexiconPath = ProcessInfo.processInfo.environment["WOLF_LEXICON"] ?? "Data/mcbopomofo/data.txt"
var segmenter: Segmenter
do {
    segmenter = Segmenter(lexicon: try Lexicon(contentsOf: URL(fileURLWithPath: lexiconPath)))
    // 調參用：WOLF_WEIGHT_chineseWord=-1、WOLF_WEIGHT_context=0 這類環境變數暫時覆蓋權重。
    let environment = ProcessInfo.processInfo.environment
    if let value = environment["WOLF_WEIGHT_chineseWord"].flatMap(Double.init) { segmenter.weights.chineseWord = value }
    if let value = environment["WOLF_WEIGHT_context"].flatMap(Double.init) { segmenter.weights.context = value }
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

case "steps":
    // 一鍵一鍵打一句話，印出每一步組字區的樣子。
    guard let result = evaluation.stability(arguments[1]) else { exit(1) }
    print(result.steps.joined(separator: " | "))

case "personal":
    // 用本機的學習紀錄評測（只在這台電腦跑，紀錄不離開本機、不進版本庫）。
    let directory = ProcessInfo.processInfo.environment["WOLF_DATA"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/WolfZhuyin")
    let verbose = arguments.dropFirst().contains("-v")
    let typos = UserTypos(fileURL: directory.appendingPathComponent("typos.json")).all
    var generic = 0, withHabits = 0
    for (mistyped, intended) in typos.sorted(by: { $0.key < $1.key }) {
        guard let target = intended.max(by: { $0.value < $1.value })?.key else { continue }
        let expected = segmenter.segment(target).map(\.text).joined()
        // 一般規則：不給個人紀錄。
        let plain = segmenter.segment(mistyped).map(\.text).joined()
        // 加上習慣：用「其他」紀錄算出來的習慣，不含這一筆本身，看它能不能類推到沒看過的錯。
        var others = typos
        others[mistyped] = nil
        var personal = segmenter
        personal.typos = UserTypos(corrections: others)
        let habitual = personal.segment(mistyped).map(\.text).joined()
        if plain == expected { generic += 1 }
        if habitual == expected { withHabits += 1 }
        if verbose { print("打錯 \(mistyped) → 想打 \(expected)：一般規則「\(plain)」、加上習慣「\(habitual)」") }
    }
    print("打錯紀錄 \(typos.count) 筆：一般規則修好 \(generic)，加上習慣（不含該筆本身）修好 \(withHabits)")

    // 反方向：正確的輸入套上個人紀錄後，不可以被改掉。詞庫常用詞與評測句子各打一次比較。
    var personal = segmenter
    personal.typos = UserTypos(corrections: typos)
    var checked = 0
    var changed: [String] = []
    var samples: [String] = []
    for entries in segmenter.lexicon.entries.values {
        if let entry = entries.first, entry.score > -5.5 { samples.append(entry.text) }
    }
    for path in ["Eval/dev.txt", "Eval/test.txt"] {
        if let content = try? String(contentsOfFile: path, encoding: .utf8) {
            samples += content.split(separator: "\n").filter { !$0.hasPrefix("#") }.map(String.init)
        }
    }
    for text in samples {
        guard let typed = evaluation.type(text) else { continue }
        checked += 1
        let plain = segmenter.segment(typed.keys).map(\.text).joined()
        let mine = personal.segment(typed.keys).map(\.text).joined()
        if plain != mine { changed.append("\(typed.keys)：\(plain) → \(mine)") }
    }
    print("正確輸入 \(checked) 筆：套上個人紀錄後結果改變 \(changed.count) 筆")
    if verbose { changed.prefix(60).forEach { print("    " + $0) } }

    let history = UserHistory(fileURL: directory.appendingPathComponent("history.json")).all
    var phrases = 0, phrasesCorrect = 0
    for (context, followers) in history where context.count == 2 && !context.contains(where: \.isASCII) {
        for (next, count) in followers where count >= UserHistory.minimumCount && !next.contains(where: \.isASCII) {
            guard let outcome = evaluation.run(context + next) else { continue }
            phrases += 1
            if outcome.textCorrect { phrasesCorrect += 1 } else if verbose { print("用詞 \(outcome.expected) → \(outcome.actual)") }
        }
    }
    // 接上用詞紀錄之後：選字會偏好自己打過的搭配。
    var learned = segmenter
    learned.history = UserHistory(fileURL: directory.appendingPathComponent("history.json"))
    let learnedEvaluation = Evaluation(segmenter: learned)
    var learnedCorrect = 0
    for (context, followers) in history where context.count == 2 && !context.contains(where: \.isASCII) {
        for (next, count) in followers where count >= UserHistory.minimumCount && !next.contains(where: \.isASCII) {
            guard let outcome = learnedEvaluation.run(context + next) else { continue }
            if outcome.textCorrect { learnedCorrect += 1 } else if verbose { print("用詞（接上紀錄後仍錯）\(outcome.expected) → \(outcome.actual)") }
        }
    }
    print("常用詞組 \(phrases) 組（出現至少 \(UserHistory.minimumCount) 次）：沒有個人紀錄時轉換正確 \(phrasesCorrect)，接上用詞紀錄後 \(learnedCorrect)")

case "stability":
    // 一鍵一鍵打評測句，列出已顯示的中文或英文後來又被改判的情況。
    var total = 0, unstable = 0
    for path in arguments.dropFirst() {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { exit(1) }
        for line in content.split(separator: "\n") where !line.hasPrefix("#") {
            guard let result = evaluation.stability(String(line)) else { continue }
            total += 1
            guard !result.flips.isEmpty else { continue }
            unstable += 1
            print("\(line)（按鍵 \(result.keys)）")
            for step in Set(result.flips.map(\.step)).sorted() {
                print("    第 \(step) 鍵：\(result.steps[max(step - 2, 0)]) → \(result.steps[step - 1])")
            }
        }
    }
    print("----\n句數 \(total)，打字途中有改判的 \(unstable) 句")

default:
    print(usage)
    exit(2)
}
