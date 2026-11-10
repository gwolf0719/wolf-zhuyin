# 狼注音

macOS 專用的注音輸入法（大千鍵盤），目標是不用按切換鍵就能中英混打。

## 功能特色
- 自動中英切換：保留原始按鍵，中文與英文兩種解讀同時評分，取總分最高的切法。
- 標點自動全形／半形：句子裡有中文出全形，純英文或夾在英數字中間出半形。
- 選字窗：按 ↓ 列出結尾字詞的其他選擇，數字鍵選取。
- 選字學習：選過的字詞下次優先，依前一個字區分（選了「我再」不會影響「他在」）。
- 符號表：按 `\` 呼叫，第一頁是常用符號；連按兩下輸出反斜線。
- 整句選字目前只看單詞頻率，尚未看上下文。
- 字詞預測：組字時提示最可能的後續，按 Tab 列出多個預測再用數字鍵選。來源是你自己打過的內容與詞庫，全部在本機。
- 打錯容錯：聲調按太早、按鍵順序顛倒、漏按聲調、按到隔壁鍵，能和旁邊的字組成常見詞時自動修正。
- 句末標點（。？！）自動送出整句。

## 技術架構
- `Sources/WolfEngine`：純 Swift 引擎，不依賴 InputMethodKit，可用命令列與測試直接驗證。
  - `Dachen`：大千按鍵 ↔ 注音。
  - `Lexicon`：中文詞庫（小麥注音 `data.txt`）。
  - `Segmenter`：中英分段與轉換。
  - `Evaluation`：把期望輸出的句子反推成按鍵，再檢查引擎能否還原。
- `Sources/wolf`：命令列工具。
- `Sources/WolfIME`：輸入法外殼（InputMethodKit）。不需要 Xcode，由 `scripts/build-app.sh` 組成 `.app`。
- `Eval/`：中英混打評測集。

## 安裝

需要 Apple Silicon 的 Mac、macOS 14 以上。在終端機執行：

```bash
curl -fsSL https://raw.githubusercontent.com/gwolf0719/wolf-zhuyin/main/install.sh | bash
```

然後到「系統設定 → 鍵盤 → 輸入方式 → 編輯 → ＋ → 繁體中文」加入「狼注音」。

### 自動更新

輸入法啟動後每天向 GitHub 查一次新版。下載的檔案要通過 Ed25519 簽章驗證才會安裝，並在你切換輸入法的空檔換成新版。

```bash
# 立刻檢查更新
~/Library/Input\ Methods/WolfZhuyin.app/Contents/MacOS/WolfZhuyin --check-update
# 關閉自動更新
defaults write tw.foso.inputmethod.WolfZhuyin AutoUpdateDisabled -bool true
```

### 移除

先在系統設定的輸入方式裡移除狼注音，再執行：

```bash
pkill -x WolfZhuyin; rm -rf ~/Library/Input\ Methods/WolfZhuyin.app ~/Library/Application\ Support/WolfZhuyin
```

## 操作

| 按鍵 | 效果 |
|---|---|
| 直接打字 | 中英文自動判斷，標點自動全形／半形 |
| `Enter` | 送出組字區的內容（句末標點也會自動送出） |
| `←` `→` | 在組字區移動游標 |
| `↓` | 對游標前的字開選字窗；數字鍵選取 |
| `\` | 符號表；連按兩下輸出反斜線 |
| `Tab` | 列出預測的後續內容；再按 `Tab` 選第一個，或按數字鍵選 |
| `。` `？` `！` | 送出整句 |
| 退格 | 刪一個字；注音打錯的按鍵串一次刪掉 |
| `Esc` | 關選字窗，或清空組字區 |

## 開發

不需要 Xcode，只要 Command Line Tools。

```bash
swift run wolf type "ji3m/4Mac283y4"   # → 我用Mac打字
make test                               # 單元測試、不變式測試、評測門檻
make eval                               # 印出中英混打評測集的結果
make install                            # 建置並裝進 ~/Library/Input Methods，再跑真實打字測試
scripts/release.sh 0.1.0                # 發版（需要簽章私鑰）
```

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
Sources/WolfUpdate/   更新邏輯（版本比對、簽章驗證）
Sources/WolfRelease/  發版簽章工具
install.sh            安裝腳本
docs/decisions.md     決策紀錄
```

## 授權

MIT，見 [LICENSE](LICENSE)。中文詞庫來自[小麥注音](https://github.com/openvanilla/McBopomofo)（MIT），見 [Data/mcbopomofo](Data/mcbopomofo/NOTICE.md)。
