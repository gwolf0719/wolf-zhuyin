# 派工協議（Dispatch Protocol）

> 統籌者（Claude Code）派任務給 CLI 實作者（agy / Codex / DeepSeek）的流程。`CLAUDE.md` 與 `AGENTS.md` 都引用本檔。
> spec 精確度由統籌者負全責；實作偏差要歸因並寫進 `docs/agent_lessons.md`。

## 角色

- **統籌者**：寫任務卡、驗收、跑最終驗證（含 `make install` 與真實打字測試）、回寫 lessons。整合層與 `Sources/WolfEngine` 的設計由統籌者負責。
- **實作者**：只改任務卡白名單內的檔案，跑指定驗證並貼結果；超出範圍就停下回報。不 commit、不 push、不安裝輸入法。

## 本專案的分配

| 工作 | 實作者 | 理由 |
| --- | --- | --- |
| 外殼 UI（`Sources/WolfIME` 內的視窗、選單） | agy | 規格清楚、檔案邊界明確 |
| 獨立審查、對照實作 | Codex（`-s read-only`） | 不同模型盲點不同 |
| 圖示等圖檔 | Codex 內建 `image_gen` | 見全域圖檔規則 |
| 引擎演算法（`Sources/WolfEngine`） | 統籌者自己做 | 需要評測集與大量來回調參，難以一次規格化 |

指令：
- agy：`agy -p "$(cat 卡.md)" --add-dir /Users/james/Project/狼注音 --model gemini-4-argon-high --dangerously-skip-permissions --print-timeout 25m`（兩個旗標放 prompt 後面）
- Codex 審查：`codex exec -s read-only -C /Users/james/Project/狼注音 -o <結果檔> - < 卡.md`

## 任務卡格式

實作者沒讀過任何對話，任務卡就是全部上下文。必含：目標、驗收條件（可客觀判定）、可改檔案白名單、禁區、既有 pattern（`path:line`）、適用 lessons 編號、驗證指令、回報格式。

派出前自檢：驗收可判定？白名單是看過程式碼列的？有指既有 pattern？驗證指令確認存在？附了 lessons？任一不過不派。

## 驗收

1. `git status` + `git diff --stat`：改動 ⊆ 白名單，越界退回。
2. 重跑 `make test`；外殼改動另跑 `make install`（含真實打字測試）並截圖目視。
3. 偏差歸因：spec 缺陷改本檔；執行缺陷寫 `docs/agent_lessons.md`（同類重犯改寫舊條）。
