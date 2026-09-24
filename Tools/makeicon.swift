//
//  makeicon.swift
//  Instant Notes
//
// Renders the app icon from the same mark as LaunchMarkView. The icon is not a scaled
// copy of that geometry: an icon is masked to a squircle and read at 40pt, so the forms
// here are fewer and much heavier. Run it when the mark changes:
//
//   swift Tools/makeicon.swift InstantNotes/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//
// Colours are the asset-catalogue values, in light appearance. An app icon is a fixed
// image — iOS does not re-render it for dark mode — so there is no dark variant here.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let side = 1024.0

// PaperTint.cream, the colour the editor actually draws a page on.
let paper = CGColor(srgbRed: 0.99, green: 0.97, blue: 0.91, alpha: 1)
// InkColor, light appearance.
let ink = CGColor(srgbRed: 0.110, green: 0.110, blue: 0.120, alpha: 1)
// RuleColor, light appearance.
let rule = CGColor(srgbRed: 0.720, green: 0.840, blue: 0.960, alpha: 1)
// The VerticalMarginLine red from the editor.
let margin = CGColor(srgbRed: 0.85, green: 0.25, blue: 0.25, alpha: 1)

// Three rows rather than the splash's four: at icon sizes, fewer and thicker reads better.
// Everything below is optically centred on the 1024 square — the leftmost edge is the
// margin rail at 157 and the rightmost is the last bar at 867, so the mark sits on 512.
let rowY = [370.0, 512.0, 654.0]
let contentX0 = 266.0
let contentX1 = 867.0
/// Per-row written width. The last row is short, so the block rags right like real writing.
let rowWidth = [320.0, 320.0, 215.0]
let inkHeight = 58.0

/// The rail, drawn heavy enough to survive being scaled to a 40pt home-screen icon.
let railX = 171.0
let railTop = 250.0
let railBottom = 775.0
let railWidth = 28.0

/// Ruling runs under the written lines and on through the waveform, which is the point:
/// both halves sit on the same baselines.
let ruleWidth = 14.0

let barX = [611.0, 679.0, 747.0, 815.0]
let barHeights = [210.0, 400.0, 270.0, 340.0]
let barWidth = 52.0

guard let ctx = CGContext(
    data: nil,
    width: Int(side),
    height: Int(side),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    FileHandle.standardError.write(Data("could not create the bitmap context\n".utf8))
    exit(1)
}

// Work in top-down coordinates, so the numbers above read the way they are drawn.
ctx.translateBy(x: 0, y: side)
ctx.scaleBy(x: 1, y: -1)

// The page, full bleed — an icon must not supply its own corners or transparency.
ctx.setFillColor(paper)
ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

// Ruling, drawn first so the waveform crosses it.
ctx.setStrokeColor(rule)
ctx.setLineWidth(ruleWidth)
ctx.setLineCap(.round)
for y in rowY {
    ctx.move(to: CGPoint(x: contentX0, y: y))
    ctx.addLine(to: CGPoint(x: contentX1, y: y))
}
ctx.strokePath()

// The margin rail.
ctx.setStrokeColor(margin)
ctx.setLineWidth(railWidth)
ctx.move(to: CGPoint(x: railX, y: railTop))
ctx.addLine(to: CGPoint(x: railX, y: railBottom))
ctx.strokePath()

// Written lines, each sitting on its rule.
ctx.setFillColor(ink)
for (i, y) in rowY.enumerated() {
    let box = CGRect(x: contentX0, y: y - inkHeight, width: rowWidth[i], height: inkHeight)
    ctx.addPath(CGPath(roundedRect: box, cornerWidth: inkHeight / 2,
                       cornerHeight: inkHeight / 2, transform: nil))
}
ctx.fillPath()

// The waveform that has not been written down yet.
for (i, x) in barX.enumerated() {
    let h = barHeights[i]
    let box = CGRect(x: x, y: 512 - h / 2, width: barWidth, height: h)
    ctx.addPath(CGPath(roundedRect: box, cornerWidth: barWidth / 2,
                       cornerHeight: barWidth / 2, transform: nil))
}
ctx.fillPath()

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.png"

guard let image = ctx.makeImage() else {
    FileHandle.standardError.write(Data("could not snapshot the context\n".utf8))
    exit(1)
}

let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write(Data("could not open \(outPath) for writing\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write(Data("could not write \(outPath)\n".utf8))
    exit(1)
}

print("wrote \(outPath) at \(Int(side))x\(Int(side))")
