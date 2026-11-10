# 狼注音（給 CLI 實作者）

macOS 注音輸入法（大千鍵盤）。Swift Package，不依賴 Xcode。專案規則與環境見 `CLAUDE.md`，決策見 `docs/decisions.md`。

## 接受派工任務卡

- 任務卡就是你的全部上下文；只改白名單內的檔案，超出範圍就停下回報。
- 開工前讀 `docs/agent_lessons.md` 中任務卡指定的編號。
- 完成後照任務卡的「回報格式」回報，貼驗證指令的輸出摘要。
- 流程與分工：`docs/dispatch_protocol.md`。
