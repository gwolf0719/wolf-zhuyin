#!/bin/bash
# 狼注音安裝腳本：下載最新版，裝進 ~/Library/Input Methods 並向系統登記。
#   curl -fsSL https://raw.githubusercontent.com/gwolf0719/wolf-zhuyin/main/install.sh | bash
# 之後輸入法會自己檢查更新（下載後驗證簽章才安裝）。
set -euo pipefail

REPO="gwolf0719/wolf-zhuyin"
DEST="$HOME/Library/Input Methods/WolfZhuyin.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "狼注音只支援 macOS" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "下載最新版…"
curl -fsSL -o "$WORK/WolfZhuyin.zip" "https://github.com/$REPO/releases/latest/download/WolfZhuyin.zip"
/usr/bin/ditto -x -k "$WORK/WolfZhuyin.zip" "$WORK"
if [[ ! -x "$WORK/WolfZhuyin.app/Contents/MacOS/WolfZhuyin" ]]; then
    echo "下載的內容不完整" >&2
    exit 1
fi

# 舊版若在執行中要先結束，系統才會載入新的執行檔。
pkill -x WolfZhuyin 2>/dev/null || true
mkdir -p "$HOME/Library/Input Methods"
rm -rf "$DEST"
cp -R "$WORK/WolfZhuyin.app" "$DEST"
"$DEST/Contents/MacOS/WolfZhuyin" --register >/dev/null

echo "已安裝狼注音 $("$DEST/Contents/MacOS/WolfZhuyin" --version)"
if "$DEST/Contents/MacOS/WolfZhuyin" --status | grep -q 已啟用; then
    echo "輸入方式裡已經有狼注音，切換過去就能用。"
else
    cat <<'NOTE'
最後一步：到「系統設定 → 鍵盤 → 輸入方式 → 編輯 → ＋ → 繁體中文」加入「狼注音」。
清單裡找不到的話，執行下面這行效果相同：
  ~/Library/Input\ Methods/WolfZhuyin.app/Contents/MacOS/WolfZhuyin --enable
NOTE
fi
