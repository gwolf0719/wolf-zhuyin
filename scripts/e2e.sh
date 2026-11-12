#!/bin/bash
# 在真實文字視窗裡切到已安裝的狼注音並送按鍵。視窗會短暫搶走焦點，所以使用者正在操作時會自動略過。
set -uo pipefail
cd "$(dirname "$0")/.."

# 測試打的字不可以記進使用者的學習紀錄（2026-11-10 發現「你好」被測試記了 66 次）。
# 測試期間關掉學習，結束時不管成功失敗都恢復原本的設定。輸入法在切換進來時會重讀設定。
DOMAIN=tw.foso.inputmethod.WolfZhuyin
previous_learning="$(defaults read "$DOMAIN" Learning 2>/dev/null || echo unset)"
restore_learning() {
    if [[ "$previous_learning" == unset ]]; then
        defaults delete "$DOMAIN" Learning 2>/dev/null || true
    else
        defaults write "$DOMAIN" Learning -bool "$([[ "$previous_learning" == 1 ]] && echo true || echo false)"
    fi
}
trap restore_learning EXIT
defaults write "$DOMAIN" Learning -bool false

failed=0
skipped=0
run() {
    .build/debug/WolfE2E "$1" "$2" 2>/dev/null
    case $? in
        0) ;;
        75) skipped=$((skipped + 1)) ;;
        *) failed=$((failed + 1)) ;;
    esac
}

run 'su3cl3{enter}' '你好'
run 'ji3m/4Mac283y4,hello world!' '我用Mac打字，hello world！'
run 'su3cl3?ji3' '你好？我'
# 送出後按退格：整段拉回組字區重改（第一下拉回，第二下才刪字）。
run 'su3cl3{enter}{delete}{delete}{enter}' '你'
run 'ji3y94ru8 {enter}{delete}{left}{down}2{enter}' '我再家'
# ↑ 直接跳到沒把握的字並開選字窗。
run 'ji3y94ru8 {up}2{enter}' '我再家'
run 'hello, world{enter}' 'hello, world'
run 'su3cl' '你ㄏㄠ'
run 'y94{down}1' '在'
run 'y94{down}1{down}1' '在'
run 'su3cl3\4' '你好？'
run 'ji3y94ru8 {left}{down}1{enter}' '我在家'
run 'su3cl3q3w{delete}{enter}' '你好'
run 's3ucl3{enter}' '你好'
run 'ji3m/4npm{enter}' '我用npm'
run 'yj/3ej/4100m06{enter}' '總共100元'
run 'C:\\Users{enter}' 'C:\Users'
run 'su3{down}8{enter}' 'su3'
run 'su3{down}9{enter}' 'ㄋㄧˇ'

if [[ $failed -gt 0 ]]; then
    echo "端對端測試：$failed 句失敗"
    exit 1
fi
if [[ $skipped -gt 0 ]]; then
    echo "端對端測試：$skipped 句因為使用者正在操作而沒有測，稍後再執行 make e2e"
    exit 0
fi
echo "端對端測試：全部通過"
