#!/bin/bash
# 不靠 Xcode，把輸入法組成 .app：swift build 出執行檔，再手動放進 bundle 結構並做 ad-hoc 簽章。
# 用法：scripts/build-app.sh            只建置到 build/狼注音.app
#       scripts/build-app.sh --install  另外裝進 ~/Library/Input Methods 並向系統登記
set -euo pipefail
cd "$(dirname "$0")/.."

# 測試沒過就不打包、不安裝。
make test

APP="build/WolfZhuyin.app"
DEST="$HOME/Library/Input Methods/WolfZhuyin.app"

swift build -c release --product WolfIME

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp App/Info.plist "$APP/Contents/Info.plist"
cp -R App/*.lproj "$APP/Contents/Resources/"
cp App/Icon/WolfZhuyin.tiff "$APP/Contents/Resources/"
cp .build/release/WolfIME "$APP/Contents/MacOS/WolfZhuyin"
cp Data/mcbopomofo/data.txt "$APP/Contents/Resources/data.txt"
cp Data/mcbopomofo/extra-characters.txt "$APP/Contents/Resources/extra-characters.txt"
codesign --force --sign - "$APP"
echo "已建置 $APP"

if [[ "${1:-}" == "--install" ]]; then
    # 舊版若在執行中要先結束，系統才會載入新的執行檔。
    pkill -x WolfZhuyin || true
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    "$DEST/Contents/MacOS/WolfZhuyin" --register
    # 已加入輸入方式時，在真實文字視窗裡實際打字驗證（視窗會短暫出現並搶走焦點）。
    if "$DEST/Contents/MacOS/WolfZhuyin" --status | grep -q 已啟用; then
        make e2e
    else
        echo "尚未加入輸入方式，略過端對端測試。加入後可執行 make e2e"
    fi
fi
