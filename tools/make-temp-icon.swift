// 임시 앱 아이콘 생성기. 실행: swiftc tools/make-temp-icon.swift -o /tmp/icon && /tmp/icon TookTook/Assets.xcassets/AppIcon.appiconset/AppIcon.png

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
// 알파 없는 RGB (App Store 아이콘은 투명도를 허용하지 않는다)
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

// 배경: 앱 강조색 파랑 그라데이션 (위가 밝음). 모서리는 iOS가 둥글게 자른다.
let gradient = CGGradient(colorsSpace: space, colors: [color(0.24, 0.60, 1.0), color(0.0, 0.40, 0.92)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: 0, y: 0), options: [])

func roundedRect(_ rect: CGRect, _ radius: CGFloat, _ fill: CGColor) {
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(fill)
    ctx.fillPath()
}

// 쌓인 카드 3장: 결제 때 남기는 '스택'. CG 좌표계는 아래가 0.
let card = CGSize(width: 560, height: 350)
let baseX = (CGFloat(size) - card.width) / 2
let layers: [(dx: CGFloat, dy: CGFloat, alpha: CGFloat)] = [(-60, 170, 0.35), (-25, 90, 0.6), (15, 0, 1.0)]
for layer in layers {
    roundedRect(CGRect(x: baseX + layer.dx, y: 230 + layer.dy, width: card.width, height: card.height), 70, color(1, 1, 1, layer.alpha))
}

// 맨 앞 카드: 기록 줄 두 개와 '톡톡' 점 두 개
let front = CGPoint(x: baseX + 15, y: 230)
roundedRect(CGRect(x: front.x + 70, y: front.y + 220, width: 250, height: 44), 22, color(0.74, 0.84, 0.99))
roundedRect(CGRect(x: front.x + 70, y: front.y + 140, width: 170, height: 44), 22, color(0.74, 0.84, 0.99))
ctx.setFillColor(color(0.0, 0.45, 0.97))
for i in 0..<2 {
    ctx.fillEllipse(in: CGRect(x: front.x + 345 + CGFloat(i) * 100, y: front.y + 70, width: 70, height: 70))
}

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
