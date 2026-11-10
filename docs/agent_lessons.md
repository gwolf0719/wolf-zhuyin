# 實作者經驗帳本

> 派工時只注入相關編號。每條：觸發情境 → 規則 → 為什麼。上限 30 條。

1. **建置與測試**：一律用 `make test`，不要直接 `swift test`，也不要用 `xcodebuild`。為什麼：這台只有 Command Line Tools，沒有 Xcode；`swift test` 找不到 Testing 模組，Makefile 已帶好路徑。
2. **不要安裝或跑真實打字測試**：不要執行 `make install`、`make e2e`、`scripts/build-app.sh --install`。為什麼：會替換使用者正在用的輸入法、搶走螢幕焦點、寫入使用者的學習紀錄；這些由統籌者做。只建置可用 `scripts/build-app.sh`（不帶參數）。
3. **WolfIME 用 Swift 5 語言模式**：`Sources/WolfIME` 在 Package.swift 設了 `.swiftLanguageMode(.v5)`，不要改成 Swift 6 嚴格併發，也不要為了消警告到處加 `@MainActor`／`Sendable`。為什麼：InputMethodKit 的 API 沒有併發標註，強行改會牽動整個外殼。
4. **介面用程式碼寫**：不要加 xib、storyboard、asset catalog、`.xcodeproj`。為什麼：專案原則是不依賴 Xcode。
5. **引擎是禁區**：外殼任務不可改 `Sources/WolfEngine` 與 `Tests/`。外殼需要的行為若引擎沒提供，停下回報。為什麼：引擎有評測集與不變式測試，改動由統籌者負責。
6. **不 commit、不 push、不發版**。為什麼：發版會觸發所有使用者自動更新。
7. **使用者看得到的文字一律繁體中文（台灣用語）**。
8. **GUI 驗收由統籌者做**：任務卡裡「開視窗看看」「點核取方塊看 defaults」這類驗收，實作者在沙箱裡做不到（Codex 的 `-s workspace-write` 建不起 NSApplication）。寫卡時把它列為「統籌者驗收」，不要列進實作者必跑的驗證，避免實作者回報 blocked。

## 9. 真實打字測試會寫進使用者的學習紀錄
`make e2e` 是透過已安裝的輸入法真的打字，打的內容會被記進 `~/Library/Application Support/WolfZhuyin/`。
2026-11-10 發現「你好」被測試記了 66 次。`scripts/e2e.sh` 現在在測試期間關掉學習、結束時恢復。
新增端對端測試或其他會經過真實輸入法的工具時，同樣不可以留下學習紀錄。
