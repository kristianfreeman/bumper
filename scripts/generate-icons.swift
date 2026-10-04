#!/usr/bin/env swift
// Generates placeholder tvOS brand assets (layered App Icon, App Store icon,
// Top Shelf images) into App/Assets.xcassets. Brand-neutral on purpose:
// replace with real artwork when the product is named.
//
// Usage: swift scripts/generate-icons.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let catalog = root.appending(path: "App/Assets.xcassets")
let brand = catalog.appending(path: "App Icon & Top Shelf Image.brandassets")
let fm = FileManager.default
try? fm.removeItem(at: brand)

func writeJSON(_ obj: Any, to url: URL) throws {
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

let info: [String: Any] = ["author": "xcode", "version": 1]
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func png(_ w: Int, _ h: Int, opaque: Bool, draw: (CGContext, CGFloat, CGFloat) -> Void) -> Data {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
    draw(ctx, CGFloat(w), CGFloat(h))
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return out as Data
}

func background(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    let colors = [CGColor(red: 0.02, green: 0.10, blue: 0.18, alpha: 1), CGColor(red: 0.0, green: 0.42, blue: 0.50, alpha: 1)] as CFArray
    let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
}

func glyph(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat, scale: CGFloat = 1) {
    // A play triangle riding a wave: "fast playback" without naming anything.
    let s = min(w, h) * 0.5 * scale
    let cx = w / 2, cy = h / 2
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
    ctx.move(to: CGPoint(x: cx - s * 0.32, y: cy - s * 0.42))
    ctx.addLine(to: CGPoint(x: cx + s * 0.48, y: cy))
    ctx.addLine(to: CGPoint(x: cx - s * 0.32, y: cy + s * 0.42))
    ctx.closePath()
    ctx.fillPath()
    ctx.setStrokeColor(CGColor(red: 0.4, green: 1, blue: 0.9, alpha: 0.9))
    ctx.setLineWidth(s * 0.07)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: cx - s * 0.9, y: cy - s * 0.62))
    ctx.addCurve(to: CGPoint(x: cx + s * 0.9, y: cy - s * 0.62), control1: CGPoint(x: cx - s * 0.3, y: cy - s * 0.95), control2: CGPoint(x: cx + s * 0.3, y: cy - s * 0.3))
    ctx.strokePath()
}

func imageset(_ dir: URL, _ sizes: [(Int, Int, String)], opaque: Bool, draw: @escaping (CGContext, CGFloat, CGFloat) -> Void) throws {
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    var images: [[String: Any]] = []
    for (w, h, scale) in sizes {
        let name = "image@\(scale).png"
        try png(w, h, opaque: opaque, draw: draw).write(to: dir.appending(path: name))
        images.append(["idiom": "tv", "filename": name, "scale": scale])
    }
    try writeJSON(["images": images, "info": info], to: dir.appending(path: "Contents.json"))
}

func imagestack(_ name: String, sizes: [(Int, Int, String)]) throws {
    let stack = brand.appending(path: "\(name).imagestack")
    try writeJSON(["layers": [["filename": "Front.imagestacklayer"], ["filename": "Back.imagestacklayer"]], "info": info], to: stack.appending(path: "Contents.json"))
    for layer in ["Front", "Back"] {
        let l = stack.appending(path: "\(layer).imagestacklayer")
        try writeJSON(["info": info], to: l.appending(path: "Contents.json"))
        try imageset(l.appending(path: "Content.imageset"), sizes, opaque: layer == "Back") { ctx, w, h in
            if layer == "Back" { background(ctx, w, h) } else { glyph(ctx, w, h) }
        }
    }
}

try imagestack("App Icon", sizes: [(400, 240, "1x"), (800, 480, "2x")])
try imagestack("App Icon - App Store", sizes: [(1280, 768, "1x")])
for (name, w, h) in [("Top Shelf Image", 1920, 720), ("Top Shelf Image Wide", 2320, 720)] {
    try imageset(brand.appending(path: "\(name).imageset"), [(w, h, "1x"), (w * 2, h * 2, "2x")], opaque: true) { ctx, w, h in
        background(ctx, w, h)
        glyph(ctx, w, h, scale: 0.8)
    }
}
try writeJSON([
    "assets": [
        ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
        ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
        ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
        ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
    ],
    "info": info,
], to: brand.appending(path: "Contents.json"))
try writeJSON(["info": info], to: catalog.appending(path: "Contents.json"))
print("Generated brand assets in \(brand.path)")
