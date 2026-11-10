#!/bin/bash
# 在真實文字視窗裡切到已安裝的狼注音並送按鍵。視窗會短暫搶走焦點，所以使用者正在操作時會自動略過。
# 選字那一句只選第一個候選（等於預設值），因為這裡會動到真實的使用者選字紀錄。
set -uo pipefail
cd "$(dirname "$0")/.."

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
run '1j4cl3{tab}{enter}' '不好意思'
run '1j4cl3{enter}{tab}{tab}{enter}' '不好意思'
run 'hello, world{enter}' 'hello, world'
run 'su3cl' '你ㄏㄠ'
run 'y94{down}1' '在'
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
