# 這台機器只有 Command Line Tools（沒有 Xcode），swift test 要自己指到內附的 Testing 框架。
CLT := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT)/Frameworks -Xlinker -F -Xlinker $(CLT)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT)/Frameworks -Xlinker -rpath -Xlinker $(CLT)/usr/lib

.PHONY: test eval install e2e icon
test:
	swift test $(TEST_FLAGS)

eval:
	swift run wolf eval Eval/dev.txt Eval/test.txt

install:
	scripts/build-app.sh --install

# 在真實文字視窗裡切到已安裝的狼注音並送按鍵。需要先把狼注音加入輸入方式。
e2e:
	swift build --product WolfE2E
	.build/debug/WolfE2E "su3cl3{enter}" "你好"
	.build/debug/WolfE2E "ji3m/4Mac283y4,hello world!{enter}" "我用Mac打字，hello world！"
	.build/debug/WolfE2E "hello, world{enter}" "hello, world"
	.build/debug/WolfE2E "su3cl" "你ㄏㄠ"
	.build/debug/WolfE2E "y94{down}1" "在"
	.build/debug/WolfE2E "su3cl3\\4" "你好？"
	.build/debug/WolfE2E "C:\\\\Users{enter}" "C:\\Users"

# 母圖換了之後重新產生選單列圖示。
icon:
	rm -rf build/icon && mkdir -p build/icon
	swift scripts/make-icon.swift App/Icon/menu-icon-master.png build/icon
	tiffutil -cathidpicheck build/icon/icon-16.png build/icon/icon-32.png -out App/Icon/WolfZhuyin.tiff
