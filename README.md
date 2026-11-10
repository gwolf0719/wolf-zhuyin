# 狼注音

macOS 專用的注音輸入法（大千鍵盤），目標是不用按切換鍵就能中英混打。

## 功能特色
- 自動中英切換：保留原始按鍵，中文與英文兩種解讀同時評分，取總分最高的切法。
- 標點自動全形／半形：句子裡有中文出全形，純英文或夾在英數字中間出半形。
- 選字窗：按 ↓ 列出結尾字詞的其他選擇，數字鍵選取。
- 選字學習：選過的字詞下次優先，依前一個字區分（選了「我再」不會影響「他在」）。
- 符號表：按 `\` 呼叫，第一頁是常用符號；連按兩下輸出反斜線。
- 整句選字目前只看單詞頻率，尚未看上下文。
- Tab 預測後續內容尚未開始（離線可用，可選擇接遠端模型）。

## 技術架構
- `Sources/WolfEngine`：純 Swift 引擎，不依賴 InputMethodKit，可用命令列與測試直接驗證。
  - `Dachen`：大千按鍵 ↔ 注音。
  - `Lexicon`：中文詞庫（小麥注音 `data.txt`）。
  - `Segmenter`：中英分段與轉換。
  - `Evaluation`：把期望輸出的句子反推成按鍵，再檢查引擎能否還原。
- `Sources/wolf`：命令列工具。
- `Sources/WolfIME`：輸入法外殼（InputMethodKit）。不需要 Xcode，由 `scripts/build-app.sh` 組成 `.app`。
- `Eval/`：中英混打評測集。

## 快速開始
```bash
swift run wolf type "ji3m/4Mac283y4"   # → 我用Mac打字
swift run wolf keys "你好"              # → su3cl3
make eval                               # 跑評測集
make test                               # 跑測試
make install                            # 建置輸入法並裝進 ~/Library/Input Methods
```
安裝後到「系統設定 → 鍵盤 → 輸入方式 → 編輯 → ＋」，在繁體中文裡加入「狼注音」。

## 專案結構
```
Sources/WolfEngine/   引擎
Sources/wolf/         命令列工具
Sources/WolfIME/      輸入法外殼
App/Info.plist        輸入法 bundle 設定
scripts/build-app.sh  不靠 Xcode 的打包腳本
Tests/                測試
Eval/                 評測集（dev 調參用、test 保留集）
Data/mcbopomofo/      中文詞庫
docs/decisions.md     決策紀錄
```
