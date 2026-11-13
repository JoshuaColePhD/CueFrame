#!/usr/bin/env swift
import AppKit

// Cueframe's selected Ribbon mark (concept 04).
// Run from the repository root to regenerate its SVG and every macOS icon size.
// SVG and PNG outputs use the same paths and colors.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("EasyDemo/Assets.xcassets/AppIcon.appiconset")
let branding = root.appendingPathComponent("assets/branding")
try FileManager.default.createDirectory(at: branding, withIntermediateDirectories: true)

func cgColor(_ hex: String) -> CGColor {
    let text = hex.replacingOccurrences(of: "#", with: "")
    let bits = UInt64(text, radix: 16)!
    let hasAlpha = text.count == 8
    let rgb = hasAlpha ? bits >> 8 : bits
    return CGColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                   green: CGFloat((rgb >> 8) & 255) / 255,
                   blue: CGFloat(rgb & 255) / 255,
                   alpha: hasAlpha ? CGFloat(bits & 255) / 255 : 1)
}
func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}
func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: x-r, y: y-r, width: r*2, height: r*2), transform: nil)
}
func polygon(_ points: [CGPoint]) -> CGPath {
    let p = CGMutablePath(); p.addLines(between: points); p.closeSubpath(); return p
}
func pathData(_ path: CGPath) -> String {
    var result = ""
    func p(_ point: CGPoint) -> String { "\(point.x) \(point.y)" }
    path.applyWithBlock { pointer in
        let e = pointer.pointee
        switch e.type {
        case .moveToPoint: result += "M\(p(e.points[0]))"
        case .addLineToPoint: result += "L\(p(e.points[0]))"
        case .addQuadCurveToPoint: result += "Q\(p(e.points[0])) \(p(e.points[1]))"
        case .addCurveToPoint: result += "C\(p(e.points[0])) \(p(e.points[1])) \(p(e.points[2]))"
        case .closeSubpath: result += "Z"
        @unknown default: break
        }
    }
    return result
}

final class Canvas {
    let context: CGContext
    var elements: [String] = []
    var definitions: [String] = ["<filter id='shadow' x='-35%' y='-35%' width='170%' height='185%'><feDropShadow dy='16' stdDeviation='16' flood-color='#101C2E' flood-opacity='.20'/></filter>"]
    init(size: Int) {
        context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size*4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
        context.translateBy(x: 0, y: 1024); context.scaleBy(x: 1, y: -1)
    }
    func shape(_ path: CGPath, fill: String? = nil, stroke: String? = nil, width: CGFloat = 0,
               gradient: [String]? = nil, shadow: Bool = false) {
        context.saveGState()
        if shadow { context.setShadow(offset: CGSize(width: 0, height: 16), blur: 32, color: cgColor("#101C2E33")) }
        var fillValue = fill ?? "none"
        if let colors = gradient {
            let id = "g\(definitions.count)"
            let stops = colors.enumerated().map { "<stop offset='\(Double($0.offset)/Double(colors.count-1))' stop-color='\($0.element)'/>" }.joined()
            definitions.append("<linearGradient id='\(id)' gradientUnits='userSpaceOnUse' x1='120' y1='100' x2='900' y2='960'>\(stops)</linearGradient>")
            fillValue = "url(#\(id))"
            context.saveGState(); context.addPath(path); context.clip()
            let cgGradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors.map(cgColor) as CFArray, locations: nil)!
            context.drawLinearGradient(cgGradient, start: CGPoint(x: 120, y: 100), end: CGPoint(x: 900, y: 960), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            context.restoreGState()
        } else if let fill {
            context.addPath(path); context.setFillColor(cgColor(fill)); context.fillPath()
        }
        if let stroke {
            context.addPath(path); context.setLineWidth(width); context.setLineCap(.round); context.setLineJoin(.round)
            context.setStrokeColor(cgColor(stroke)); context.strokePath()
        }
        elements.append("<path d='\(pathData(path))' fill='\(fillValue)' stroke='\(stroke ?? "none")' stroke-width='\(width)' stroke-linecap='round' stroke-linejoin='round'\(shadow ? " filter='url(#shadow)'" : "")/>")
        context.restoreGState()
    }
    func tile(_ colors: [String]) {
        let tile = rounded(96, 96, 832, 832, 184)
        shape(tile, fill: colors.last!, shadow: true)
        shape(tile, stroke: "#FFFFFF24", width: 2, gradient: colors)
    }
    func clip(_ path: CGPath, _ draw: () -> Void) {
        let id = "clip\(definitions.count)"
        definitions.append("<clipPath id='\(id)'><path d='\(pathData(path))'/></clipPath>")
        elements.append("<g clip-path='url(#\(id))'>")
        context.saveGState(); context.addPath(path); context.clip(); draw(); context.restoreGState()
        elements.append("</g>")
    }
    var image: CGImage { context.makeImage()! }
    var png: Data { NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])! }
    func svg(title: String) -> String {
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1024 1024' role='img' aria-labelledby='title'><title id='title'>Cueframe — \(title)</title><defs>\(definitions.joined())</defs>\(elements.joined())</svg>"
    }
}

func drawRibbon(_ c: Canvas) {
        c.tile(["#9171F8", "#6944D4", "#43288E"])
        let left = CGMutablePath(); left.move(to: CGPoint(x: 346, y: 271))
        left.addCurve(to: CGPoint(x: 278, y: 339), control1: CGPoint(x: 303, y: 246), control2: CGPoint(x: 278, y: 270))
        left.addLine(to: CGPoint(x: 278, y: 689))
        left.addCurve(to: CGPoint(x: 350, y: 752), control1: CGPoint(x: 278, y: 756), control2: CGPoint(x: 308, y: 776))
        left.addLine(to: CGPoint(x: 505, y: 657)); left.addLine(to: CGPoint(x: 407, y: 600))
        left.addLine(to: CGPoint(x: 407, y: 378)); left.addLine(to: CGPoint(x: 346, y: 271)); left.closeSubpath()
        c.shape(left, fill: "#E9DEFF")
        c.shape(polygon([.init(x: 346,y: 271),.init(x: 737,y: 471),.init(x: 616,y: 541),.init(x: 407,y: 426),.init(x: 407,y: 378)]), fill: "#F7EFFF")
        let lower = polygon([.init(x: 737,y: 471),.init(x: 737,y: 551),.init(x: 350,y: 752),.init(x: 407,y: 600),.init(x: 616,y: 481)])
        c.shape(lower, fill: "#B5F2E3")
        c.shape(polygon([.init(x: 407,y: 600),.init(x: 407,y: 694),.init(x: 350,y: 752)]), fill: "#BDA3ED")
}
let master = Canvas(size: 1024)
drawRibbon(master)
try master.png.write(to: root.appendingPathComponent("assets/AppIcon.png"))
try Data(master.svg(title: "Ribbon").utf8).write(to: branding.appendingPathComponent("Cueframe.svg"))
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: iconset.appendingPathComponent("Contents.json"))) as! [String: Any]
for item in manifest["images"] as! [[String: String]] {
    let points = Int(item["size"]!.split(separator: "x")[0])!
    let scale = item["scale"] == "2x" ? 2 : 1
    let canvas = Canvas(size: points * scale)
    drawRibbon(canvas)
    try canvas.png.write(to: iconset.appendingPathComponent(item["filename"]!))
}
print("Generated Cueframe Ribbon SVG and all 10 macOS app icon renditions.")
