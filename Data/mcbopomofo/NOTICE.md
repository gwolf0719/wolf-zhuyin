# 詞庫來源

`data.txt` 取自小麥注音（McBopomofo）2.9.5 的 `Contents/Resources/data.txt`，MIT 授權，授權全文見同目錄 `LICENSE.txt`。
原專案：https://github.com/openvanilla/McBopomofo

## 罕用字補充表

`extra-characters.txt` 不是小麥注音的檔案：它列出 `data.txt` 沒收的字（例如「饍」），由 `scripts/gen-extra-characters.swift` 用 macOS 內建的 Unicode 讀音資料產生，分數固定為最低。要重新產生：

    swift scripts/gen-extra-characters.swift > Data/mcbopomofo/extra-characters.txt
