# 狼注音

macOS 專用注音輸入法（大千鍵盤）：自動中英切換、整句選字、Tab 預測（預測尚未開始）。

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
- 公開專案：https://github.com/gwolf0719/wolf-zhuyin （MIT）。
- **發版＝對外發布，要使用者同意才做**：`scripts/release.sh <版本號>`（測試 → 寫版本號 → 打包 → 簽章 → push ＋ GitHub Release）。已安裝的輸入法每天查一次，會自動裝上新版。
- 簽章私鑰在 `~/.config/wolf-zhuyin/release-signing-key`（不在版本庫）。對應公鑰寫死在 `Sources/WolfUpdate/Update.swift`。**私鑰遺失或外洩都要換金鑰，而已安裝的舊版只認舊公鑰，使用者得重新跑安裝指令。**
- 沒有 Apple Developer ID：成品只有 ad-hoc 簽章。靠 `install.sh`（curl 下載不會被 Gatekeeper 隔離）安裝；不要改成讓人從瀏覽器下載 `.app`／`.pkg`，會被擋。
- 只建置 arm64（Command Line Tools 建不了 universal）。
- 確認發版狀態：`gh release list -R gwolf0719/wolf-zhuyin`；已安裝版本：`WolfZhuyin --version`；手動觸發更新：`WolfZhuyin --check-update`。
