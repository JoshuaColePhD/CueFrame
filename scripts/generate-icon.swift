#!/usr/bin/env swift
import AppKit

// Cueframe's original vector mark. Run from the repository root to regenerate
// the SVG and all macOS icon sizes. No external design tools are required.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("EasyDemo/Assets.xcassets/AppIcon.appiconset")
let branding = root.appendingPathComponent("assets/branding")
try FileManager.default.createDirectory(at: branding, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: width, height: height),
           cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func gradient(_ context: CGContext, _ path: CGPath, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    context.saveGState(); context.addPath(path); context.clip()
    let value = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: colors as CFArray, locations: nil)!
    context.drawLinearGradient(value, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
}
func render(size: Int) throws -> Data {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    context.translateBy(x: 0, y: 1024); context.scaleBy(x: 1, y: -1)
    let tile = rounded(96, 96, 832, 832, 184)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 18), blur: 30, color: color(0x07142E, alpha: 0.25))
    context.setFillColor(color(0x18264B)); context.addPath(tile); context.fillPath()
    context.restoreGState()
    gradient(context, tile, [color(0x2F4C8C), color(0x172649), color(0x111A33)],
             from: CGPoint(x: 180, y: 110), to: CGPoint(x: 830, y: 940))
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.18)); context.setLineWidth(2)
    context.addPath(tile); context.strokePath()

    let screen = rounded(218, 280, 588, 390, 58)
    gradient(context, screen, [color(0x3C6498), color(0x20345B)],
             from: CGPoint(x: 220, y: 280), to: CGPoint(x: 800, y: 670))
    context.setLineWidth(32); context.setStrokeColor(color(0xE9FAF6))
    context.addPath(screen); context.strokePath()

    let play = CGMutablePath()
    play.move(to: CGPoint(x: 447, y: 392)); play.addLine(to: CGPoint(x: 447, y: 551))
    play.addLine(to: CGPoint(x: 566, y: 471)); play.closeSubpath()
    context.setFillColor(color(0xE9FAF6)); context.setStrokeColor(color(0xE9FAF6))
    context.setLineWidth(12); context.setLineJoin(.round)
    context.addPath(play); context.drawPath(using: .fillStroke)

    let camera = rounded(566, 510, 258, 258, 76)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 12), blur: 22, color: color(0x07142E, alpha: 0.38))
    context.setFillColor(color(0x6DE4C8)); context.addPath(camera); context.fillPath()
    context.restoreGState()
    gradient(context, camera, [color(0xA4F8DF), color(0x61D9BF)],
             from: CGPoint(x: 570, y: 510), to: CGPoint(x: 820, y: 770))
    context.setStrokeColor(color(0xD3FFF1, alpha: 0.85)); context.setLineWidth(5)
    context.addPath(camera); context.strokePath()
    context.setFillColor(color(0x183B4A))
    context.fillEllipse(in: CGRect(x: 665, y: 563, width: 60, height: 60))
    let shoulders = CGMutablePath()
    shoulders.move(to: CGPoint(x: 635, y: 701))
    shoulders.addCurve(to: CGPoint(x: 695, y: 641), control1: CGPoint(x: 635, y: 660), control2: CGPoint(x: 659, y: 641))
    shoulders.addCurve(to: CGPoint(x: 755, y: 701), control1: CGPoint(x: 731, y: 641), control2: CGPoint(x: 755, y: 660))
    shoulders.addQuadCurve(to: CGPoint(x: 741, y: 715), control: CGPoint(x: 755, y: 715))
    shoulders.addLine(to: CGPoint(x: 649, y: 715))
    shoulders.addQuadCurve(to: CGPoint(x: 635, y: 701), control: CGPoint(x: 635, y: 715)); shoulders.closeSubpath()
    context.addPath(shoulders); context.fillPath()
    let image = context.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-labelledby="title">
  <title id="title">Cueframe — screen and camera together</title>
  <defs>
    <linearGradient id="tile" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#2F4C8C"/><stop offset=".5" stop-color="#172649"/><stop offset="1" stop-color="#111A33"/></linearGradient>
    <linearGradient id="screen" x2="1" y2="1"><stop stop-color="#3C6498"/><stop offset="1" stop-color="#20345B"/></linearGradient>
    <linearGradient id="camera" x2="1" y2="1"><stop stop-color="#A4F8DF"/><stop offset="1" stop-color="#61D9BF"/></linearGradient>
    <filter id="shadow" x="-25%" y="-25%" width="150%" height="165%"><feDropShadow dy="18" stdDeviation="15" flood-color="#07142E" flood-opacity=".25"/></filter>
    <filter id="camera-shadow" x="-25%" y="-25%" width="150%" height="165%"><feDropShadow dy="12" stdDeviation="11" flood-color="#07142E" flood-opacity=".38"/></filter>
  </defs>
  <rect x="96" y="96" width="832" height="832" rx="184" fill="url(#tile)" stroke="#fff" stroke-opacity=".18" stroke-width="2" filter="url(#shadow)"/>
  <rect x="218" y="280" width="588" height="390" rx="58" fill="url(#screen)" stroke="#E9FAF6" stroke-width="32"/>
  <path d="M447 392V551L566 471Z" fill="#E9FAF6" stroke="#E9FAF6" stroke-width="12" stroke-linejoin="round"/>
  <rect x="566" y="510" width="258" height="258" rx="76" fill="url(#camera)" stroke="#D3FFF1" stroke-opacity=".85" stroke-width="5" filter="url(#camera-shadow)"/>
  <circle cx="695" cy="593" r="30" fill="#183B4A"/>
  <path d="M635 701C635 660 659 641 695 641S755 660 755 701Q755 715 741 715H649Q635 715 635 701Z" fill="#183B4A"/>
</svg>
"""
try Data(svg.utf8).write(to: branding.appendingPathComponent("Cueframe.svg"))
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: iconset.appendingPathComponent("Contents.json"))) as! [String: Any]
for item in manifest["images"] as! [[String: String]] {
    let points = Int(item["size"]!.split(separator: "x")[0])!
    let scale = item["scale"] == "2x" ? 2 : 1
    try render(size: points * scale).write(to: iconset.appendingPathComponent(item["filename"]!))
}
try render(size: 1024).write(to: root.appendingPathComponent("assets/AppIcon.png"))
print("Generated Cueframe SVG and all 10 macOS app icon renditions.")
