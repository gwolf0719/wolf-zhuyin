// 產生 Data/mcbopomofo/extra-characters.txt：詞庫沒收的罕用字（饍、堃…），讀音取自系統內建的 Unicode 資料。
// 用法：swift scripts/gen-extra-characters.swift > Data/mcbopomofo/extra-characters.txt
import Foundation

let data = try! String(contentsOfFile: "Data/mcbopomofo/data.txt", encoding: .utf8)
var known: Set<String> = []
var syllables: Set<String> = []
for line in data.split(separator: "\n") {
    let fields = line.split(separator: " ")
    guard fields.count == 3, !line.hasPrefix("#"), !line.hasPrefix("_") else { continue }
    if fields[1].count == 1 { known.insert(String(fields[1])) }
    if !fields[0].contains("-") { syllables.insert(String(fields[0])) }
}

func transformed(_ text: String, _ id: String) -> String {
    let buffer = NSMutableString(string: text)
    CFStringTransform(buffer, nil, id as CFString, false)
    return buffer as String
}

print("# 詞庫沒收的罕用字。由 scripts/gen-extra-characters.swift 產生，不要手改。")
print("# 分數固定比詞庫最罕用的字還低，只會排在選字窗最後面。")
var lines: [String] = []
for range in [0x4E00...0x9FFF] {
    for value in range {
        let character = String(UnicodeScalar(value)!)
        guard !known.contains(character) else { continue }
        // 簡體字不收（轉成繁體會變的就是簡體）。
        guard transformed(character, "Simplified-Traditional") == character else { continue }
        let latin = transformed(character, "Han-Latin")
        guard latin != character else { continue }
        let reading = transformed(latin, "Latin-Bopomofo")
        guard syllables.contains(reading) else { continue }
        lines.append("\(reading) \(character) -9.0")
    }
}
print(lines.sorted().joined(separator: "\n"))
