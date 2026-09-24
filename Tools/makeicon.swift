//
//  makeicon.swift
//  Quolio
//
// Renders the app icon from the same mark as LaunchMarkView: a speech bubble holding a
// bulleted recap — the splash's last frame, once the waveform has been written up. Run it
// when the mark changes:
//
//   swift Tools/makeicon.swift InstantNotes/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//
// Pass `--logo` after the path for a standalone logo: the same art with rounded,
// transparent corners, for use outside the App Store (web, press, slides).
//
// An app icon is a fixed image — iOS does not re-render it for dark mode — so there is no
// dark variant here.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let side = 1024.0
let logo = CommandLine.arguments.contains("--logo")

// The tile: AccentColor (#3B5BCC) sits in the middle of this gradient.
let tileTop = CGColor(srgbRed: 0.318, green: 0.443, blue: 0.894, alpha: 1)
let tileBottom = CGColor(srgbRed: 0.176, green: 0.267, blue: 0.667, alpha: 1)
// PaperTint.cream, the colour the editor draws a page on.
let paper = CGColor(srgbRed: 0.99, green: 0.97, blue: 0.91, alpha: 1)
// InkColor, light appearance.
let ink = CGColor(srgbRed: 0.110, green: 0.110, blue: 0.120, alpha: 1)
// AccentColor.
let accent = CGColor(srgbRed: 0.231, green: 0.357, blue: 0.800, alpha: 1)

// The bubble, optically centred once its tail is counted.
let bubble = CGRect(x: 170, y: 190, width: 684, height: 520)
let bubbleRadius = 160.0

// Three recap rows, shortening down the list. LaunchMarkView.lineWidth scaled to this tile.
let rowY = [352.0, 452.0, 552.0]
let bulletX = 272.0
let bulletRadius = 30.0
let lineX = 340.0
let rowWidth = [450.0, 369.0, 246.0]
let lineHeight = 54.0

guard let ctx = CGContext(
    data: nil,
    width: Int(side),
    height: Int(side),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: logo ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    FileHandle.standardError.write(Data("could not create the bitmap context\n".utf8))
    exit(1)
}

// Work in top-down coordinates, so the numbers above read the way they are drawn.
ctx.translateBy(x: 0, y: side)
ctx.scaleBy(x: 1, y: -1)

// The tile, full bleed for the icon — an icon must not supply its own corners or
// transparency. The logo rounds them itself.
if logo {
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side),
                       cornerWidth: side * 0.225, cornerHeight: side * 0.225, transform: nil))
    ctx.clip()
}
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [tileTop, tileBottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: side), options: [])

// The bubble and its tail, lifted off the tile by a soft shadow.
let tail = CGMutablePath()
tail.move(to: CGPoint(x: 262, y: 660))
tail.addQuadCurve(to: CGPoint(x: 196, y: 842), control: CGPoint(x: 268, y: 780))
tail.addQuadCurve(to: CGPoint(x: 430, y: 700), control: CGPoint(x: 340, y: 800))
tail.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 48,
              color: CGColor(srgbRed: 0.05, green: 0.08, blue: 0.25, alpha: 0.35))
ctx.setFillColor(paper)
// One transparency layer, so the shadow is cast once by the joined outline.
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.addPath(CGPath(roundedRect: bubble, cornerWidth: bubbleRadius, cornerHeight: bubbleRadius, transform: nil))
ctx.fillPath()
ctx.addPath(tail)
ctx.fillPath()
ctx.endTransparencyLayer()
ctx.restoreGState()

// Bullets, in the accent, so the rows read as a recap rather than as prose.
ctx.setFillColor(accent)
for y in rowY {
    ctx.fillEllipse(in: CGRect(x: bulletX - bulletRadius, y: y - bulletRadius,
                               width: bulletRadius * 2, height: bulletRadius * 2))
}

// Written lines.
ctx.setFillColor(ink)
for (i, y) in rowY.enumerated() {
    let box = CGRect(x: lineX, y: y - lineHeight / 2, width: rowWidth[i], height: lineHeight)
    ctx.addPath(CGPath(roundedRect: box, cornerWidth: lineHeight / 2,
                       cornerHeight: lineHeight / 2, transform: nil))
}
ctx.fillPath()

let outPath = CommandLine.arguments.count > 1 && !CommandLine.arguments[1].hasPrefix("--")
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
