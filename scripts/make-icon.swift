// 從 Codex 產生的母圖（App/Icon/menu-icon-master.png）衍生選單列圖示。
// 只做去掉四角白底與縮放，不重畫內容：衍生版本必須與母圖逐點一致，所以用程式處理。
// 用法：swift scripts/make-icon.swift <母圖.png> <輸出資料夾>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let source = NSImage(contentsOfFile: arguments[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("用法：swift scripts/make-icon.swift <母圖.png> <輸出資料夾>")
    exit(2)
}

let width = source.width, height = source.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let context = CGContext(
    data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

// 從四個角往內找相連的近白色像素，改成透明。徽章內部的淺色不相連，不受影響。
func isBackground(_ index: Int) -> Bool {
    pixels[index * 4 + 3] > 0 && pixels[index * 4] > 200 && pixels[index * 4 + 1] > 200 && pixels[index * 4 + 2] > 200
}
var stack = [0, width - 1, (height - 1) * width, height * width - 1]
while let index = stack.popLast() {
    guard isBackground(index) else { continue }
    for offset in 0..<4 { pixels[index * 4 + offset] = 0 }
    let x = index % width, y = index / width
    if x > 0 { stack.append(index - 1) }
    if x < width - 1 { stack.append(index + 1) }
    if y > 0 { stack.append(index - width) }
    if y < height - 1 { stack.append(index + width) }
}

let masked = context.makeImage()!
for size in [16, 32] {
    let scaled = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    scaled.interpolationQuality = .high
    scaled.draw(masked, in: CGRect(x: 0, y: 0, width: size, height: size))
    let data = NSBitmapImageRep(cgImage: scaled.makeImage()!).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: arguments[2]).appendingPathComponent("icon-\(size).png"))
}
