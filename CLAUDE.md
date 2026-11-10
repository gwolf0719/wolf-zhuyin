# 狼注音

macOS 專用注音輸入法（大千鍵盤）：自動中英切換、整句選字、Tab 預測。

## 系統環境
- Swift 6.3（Swift Package）：引擎 `WolfEngine`、命令列 `wolf`、輸入法外殼 `WolfIME`、端對端測試 `WolfE2E`。
- **原則：整個專案不依賴 Xcode.app，只用 Command Line Tools**（2026-11-10 使用者定案）。不加 .xcodeproj、xib、storyboard、asset catalog；介面用程式碼寫。
  - `swift test` 直接跑會找不到 `Testing` 模組，一律用 `make test`（Makefile 已帶好框架路徑）。
  - 輸入法 `.app` 由 `scripts/build-app.sh` 手動組 bundle + ad-hoc 簽章，`make install` 裝進 `~/Library/Input Methods/` 並登記。
  - 改了輸入法程式後重裝，腳本會結束舊的 `WolfZhuyin` 行程，系統下次切到狼注音時才會載入新版。
- 中文詞庫：`Data/mcbopomofo/data.txt`（小麥注音，MIT，見同目錄 NOTICE.md）。
- 英文詞表：系統的 `/usr/share/dict/words` + `EnglishWords.swift` 內的常用字清單，沒有詞頻，是暫時方案。

## 驗證
- 打字行為（按鍵 → 組字區 → 送出）寫在引擎的 `Composer`，外殼只做事件轉接；新增行為時在 `ComposerTests` 補測試，不要把邏輯寫進 `WolfIME`。
- `make test`：單元測試、不變式測試、評測集正確率門檻。
- `make install`：先跑 `make test`，通過才建置並安裝輸入法；`WolfZhuyin --status` 可查系統是否認得、是否啟用。實際打字要人在系統設定啟用後手動試。
- `make e2e`：在真實文字視窗切到已安裝的狼注音、送鍵盤事件、比對文字框內容（`make install` 會自動跑）。
  - 送鍵一定要用 `CGEvent` 包成的 `NSEvent`；手工拼的 `NSEvent.keyEvent` 不會被系統轉給輸入法，任何輸入法都測不過。
  - 終端機會印 `error messaging the mach port for IMKCFRunLoopWakeUpReliable`，是雜訊，不代表失敗。
  - 系統給輸入模式的識別碼是 `tw.foso.inputmethod.WolfZhuyin.WolfZhuyin.Zhuyin`（中間多一段 bundle 名稱），不是 Info.plist 裡寫的 key。
- 除錯紀錄：`touch ~/Library/Logs/WolfZhuyin.debug` 後，伺服器會寫 `~/Library/Logs/WolfZhuyin.log`（啟動、連線、每次按鍵有沒有被處理；不含按鍵內容）。刪掉該檔即關閉。
- 圖示：母圖 `App/Icon/menu-icon-master.png` 由 Codex `image_gen` 產生；`make icon` 用程式去掉白角並縮成選單列用的 tiff（衍生版本須與母圖一致，所以不重新生圖）。
- `make eval`：印出評測集每一句的錯誤與正確率。
- `Eval/dev.txt` 可以看錯誤來調參；`Eval/test.txt` 是保留集，只回報數字，不針對它調。

## 部署
尚無。自用為主，保留公開發行的可能（屆時需 Developer ID 簽章與 notarization）。
