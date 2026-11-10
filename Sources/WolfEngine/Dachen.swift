/// 大千（標準）注音鍵盤配置。
public enum Dachen {
    static let consonants: [Character: Character] = [
        "1": "ㄅ", "q": "ㄆ", "a": "ㄇ", "z": "ㄈ", "2": "ㄉ", "w": "ㄊ", "s": "ㄋ",
        "x": "ㄌ", "e": "ㄍ", "d": "ㄎ", "c": "ㄏ", "r": "ㄐ", "f": "ㄑ", "v": "ㄒ",
        "5": "ㄓ", "t": "ㄔ", "g": "ㄕ", "b": "ㄖ", "y": "ㄗ", "h": "ㄘ", "n": "ㄙ",
    ]
    static let medials: [Character: Character] = ["u": "ㄧ", "j": "ㄨ", "m": "ㄩ"]
    static let rimes: [Character: Character] = [
        "8": "ㄚ", "i": "ㄛ", "k": "ㄜ", ",": "ㄝ", "9": "ㄞ", "o": "ㄟ", "l": "ㄠ",
        ".": "ㄡ", "0": "ㄢ", "p": "ㄣ", ";": "ㄤ", "/": "ㄥ", "-": "ㄦ",
    ]
    /// 聲調鍵 → 詞庫裡的聲調記號（一聲為空字串）。
    static let tones: [Character: String] = [" ": "", "6": "ˊ", "3": "ˇ", "4": "ˋ", "7": "˙"]

    /// 注音符號或聲調記號 → 按鍵（給評測用的「模擬打字」反查）。
    static let keyForSymbol: [Character: Character] = {
        var map: [Character: Character] = [:]
        for table in [consonants, medials, rimes] {
            for (key, symbol) in table { map[symbol] = key }
        }
        for (key, mark) in tones where !mark.isEmpty { map[Character(mark)] = key }
        return map
    }()

    /// 從 `keys[start]` 起解析一個完整音節（聲母→介音→韻母→聲調，照標準順序）。
    /// 只檢查結構，音節是否真的存在由詞庫判斷。
    static func syllable(in keys: [Character], from start: Int) -> (reading: String, end: Int)? {
        var position = start
        var reading = ""
        for table in [consonants, medials, rimes] {
            if position < keys.count, let symbol = table[keys[position]] {
                reading.append(symbol)
                position += 1
            }
        }
        guard !reading.isEmpty, position < keys.count, let tone = tones[keys[position]] else {
            return nil
        }
        return (reading + tone, position + 1)
    }

    /// 鍵盤上相鄰的鍵（同一排左右，以及上下排斜對的兩個）。
    static let neighbors: [Character: [Character]] = {
        let rows = ["1234567890-", "qwertyuiop", "asdfghjkl;", "zxcvbnm,./"].map(Array.init)
        var map: [Character: [Character]] = [:]
        func link(_ a: Character, _ b: Character) {
            map[a, default: []].append(b)
            map[b, default: []].append(a)
        }
        for (rowIndex, row) in rows.enumerated() {
            for (column, key) in row.enumerated() {
                if column + 1 < row.count { link(key, row[column + 1]) }
                // 每一排比上一排往右錯開半個鍵：q 在 1 和 2 的下方。
                if rowIndex > 0 {
                    let above = rows[rowIndex - 1]
                    for aboveColumn in [column, column + 1] where aboveColumn < above.count { link(key, above[aboveColumn]) }
                }
            }
        }
        return map
    }()

    /// 一組按鍵若是「聲母、介音、韻母各至多一個，加上剛好一個聲調」，不管順序，回傳音節讀音。
    static func syllable(fromUnordered keys: ArraySlice<Character>) -> String? {
        var consonant: Character?, medial: Character?, rime: Character?, tone: String?
        for key in keys {
            if let symbol = consonants[key], consonant == nil { consonant = symbol }
            else if let symbol = medials[key], medial == nil { medial = symbol }
            else if let symbol = rimes[key], rime == nil { rime = symbol }
            else if let mark = tones[key], tone == nil { tone = mark }
            else { return nil }
        }
        guard let tone, consonant != nil || medial != nil || rime != nil else { return nil }
        return String([consonant, medial, rime].compactMap { $0 }) + tone
    }

    static func isSymbolKey(_ key: Character) -> Bool {
        consonants[key] != nil || medials[key] != nil || rimes[key] != nil
    }

    /// 一串按鍵若剛好照「聲母→介音→韻母」排列（不含聲調），回傳對應的注音符號。
    static func symbols(for keys: ArraySlice<Character>) -> String? {
        var remaining = keys
        var result = ""
        for table in [consonants, medials, rimes] {
            if let key = remaining.first, let symbol = table[key] {
                result.append(symbol)
                remaining = remaining.dropFirst()
            }
        }
        return remaining.isEmpty && !result.isEmpty ? result : nil
    }

    /// 讀音（如 `ㄋㄧˇ-ㄏㄠˇ`）→ 按鍵序列（`su3cl3`）。
    static func keys(forReading reading: String) -> String? {
        var result = ""
        for syllable in reading.split(separator: "-") {
            var hasTone = false
            for symbol in syllable {
                guard let key = keyForSymbol[symbol] else { return nil }
                if tones[key] != nil { hasTone = true }
                result.append(key)
            }
            if !hasTone { result.append(" ") }
        }
        return result
    }
}
