#!/bin/bash
# 發版：scripts/release.sh 0.1.0
# 測試 → 寫入版本號 → 打包 → 簽章 → 推到 GitHub 並建立 Release。
# 私鑰在 ~/.config/wolf-zhuyin/release-signing-key，不在版本庫裡；遺失就無法再發自動更新。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?用法：scripts/release.sh <版本號，例如 0.1.0>}"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "版本號只能是數字與點" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "工作區有未提交的改動，先 commit" >&2; exit 1; }

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" App/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" App/Info.plist

scripts/build-app.sh
swift build --product WolfRelease

rm -f build/WolfZhuyin.zip build/WolfZhuyin.zip.sig
/usr/bin/ditto -c -k --keepParent build/WolfZhuyin.app build/WolfZhuyin.zip
.build/debug/WolfRelease sign build/WolfZhuyin.zip > build/WolfZhuyin.zip.sig
.build/debug/WolfRelease verify build/WolfZhuyin.zip build/WolfZhuyin.zip.sig

git commit -qam "發版 v$VERSION"
git tag "v$VERSION"
git push -q origin main "v$VERSION"
gh release create "v$VERSION" build/WolfZhuyin.zip build/WolfZhuyin.zip.sig \
    --title "狼注音 v$VERSION" --notes "${2:-安裝與更新方式見 README。}"
echo "已發版 v$VERSION"
