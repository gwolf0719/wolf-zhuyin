# 狼注音

macOS 專用的注音輸入法（大千鍵盤），目標是不用按切換鍵就能中英混打。

## 功能特色
- 自動中英切換：保留原始按鍵，中文與英文兩種解讀同時評分，取總分最高的切法。
- 標點自動全形／半形：句子裡有中文出全形，純英文或夾在英數字中間出半形。
- 打字途中不跳動：打到一半的音節先顯示注音，已經顯示的中文不會因為下一鍵變回英文。
- 選字窗：按 ↓ 列出游標前字詞的其他選擇，數字鍵選取。第一頁最後幾個選項是「可能是打錯」的修正、照打的英文、注音符號本身。選過的字可以再改。
- 選字學習：選過的字詞下次優先，依前一個字區分（選了「我再」不會影響「他在」）。
- 選字看上下文：完整的詞優先（明天再說）、數字後面的量詞（100元）、句尾語助詞（go吧）。
- 符號表：按 `\` 呼叫，第一頁是常用符號（含半形的 `[` `]`：`\8`、`\9`）；連按兩下輸出反斜線。
- 包住選取的文字：先選一段文字再按 `\`，會列出成對的標點（「」『』（）《》【】…），選一個就把那段包起來；`Esc` 取消。
- 字詞預測：組字時提示最可能的後續，按 Tab 列出多個預測再用數字鍵選；送出後緊接著按 Tab 可預測接下來的內容或下一句開頭。來源是你自己打過的內容與詞庫，全部在本機。
- 打錯容錯：打得出正確注音的一律照打；拼不成注音的按鍵（順序顛倒、漏按聲調、按到隔壁、多按或漏按一鍵）才自動修正。其他可能的修正放在選字窗裡。
- 本機模型預測（實驗，預設關閉）：macOS 26 並開啟 Apple Intelligence 時，可在設定打開，停頓一下就會看整句的意思續寫。全程在本機，不連網。
- 學你的打錯習慣：退格後重打就記成一次更正；同一類打錯累積 3 次，同類沒見過的也會修。
- 句末標點（。？！）自動送出整句。
- 學習紀錄（輸入法選單 →「學習紀錄…」）：看得到輸入法學了哪些選字、用詞、打錯，可以搜尋、刪掉不要的。
- 設定（輸入法選單 →「狼注音設定…」）：中英文之間自動加空白、打錯容錯、學習、預測、自動更新。

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
| `↑` | 直接跳到輸入法沒把握的字（有分數相近的同音字、或沒認出來的按鍵）並開選字窗；再按往左找下一個 |
| `↓` | 對游標前的字開選字窗；數字鍵選取。第一頁最後兩個是照打的英文、注音符號；在標點後按 ↓ 可改回照打的半形（「」→ []） |
| `\` | 符號表；連按兩下輸出反斜線 |
| 選取文字後按 `\` | 列出成對的標點，把選取的文字包起來 |
| `Tab` | 有預測提示時列出後續內容；再按 `Tab` 選第一個，或按數字鍵選。預測只在夠有把握時出現（你自己打過 3 次以上、而且佔那段前文一半以上） |
| `。` `？` `！` | 送出整句 |
| 退格 | 刪一個字；注音打錯的按鍵串一次刪掉。**剛送出就按退格**：把整段拉回組字區重改（app 不支援時照常刪一個字） |
| `Esc` | 關選字窗，或清空組字區 |

## 開發

不需要 Xcode，只要 Command Line Tools。

```bash
swift run wolf type "ji3m/4Mac283y4"   # → 我用Mac打字
make test                               # 單元測試、不變式測試、評測門檻
make eval                               # 印出中英混打評測集的結果
make install                            # 建置並裝進 ~/Library/Input Methods，再跑真實打字測試
make personal                           # 用本機的學習紀錄評測（紀錄不離開本機）
swift run wolf steps "因為他不在"        # 一鍵一鍵打，看每一步組字區的樣子
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
