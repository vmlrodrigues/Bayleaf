// Generates Resources/AppIcon.icns via:
//
//   swift Scripts/make-icon.swift
//   iconutil -c icns dist/AppIcon.iconset -o Resources/AppIcon.icns
//
// Design: a white page, corner folded, with a bay leaf lying across it — the pun the
// app is named for (a leaf IS a page; a bay leaf is the one you fish out and keep). Deep botanical green tile so
// it reads instantly in a Dock full of blues and whites.
//
// Same scheme as ClawBar's: everything is a fraction of the canvas, so all ten
// iconset sizes are the same drawing re-executed rather than one bitmap scaled.

import AppKit

func makeIcon(_ S: CGFloat) -> CGImage {
    let space = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S),
                        bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let pad = S * 0.094
    let body = CGRect(x: pad, y: pad, width: S - 2 * pad, height: S - 2 * pad)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: S * 0.181,
                          cornerHeight: S * 0.181, transform: nil)

    // Drop shadow under the whole tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.014), blur: S * 0.035,
                  color: NSColor.black.withAlphaComponent(0.40).cgColor)
    ctx.addPath(bodyPath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()

    // Deep green base, lit from the top-left.
    let base = CGGradient(colorsSpace: space, colors: [
        NSColor(srgbRed: 0.10, green: 0.30, blue: 0.22, alpha: 1).cgColor,
        NSColor(srgbRed: 0.03, green: 0.12, blue: 0.10, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY), options: [])

    // Top sheen.
    let sheen = CGGradient(colorsSpace: space, colors: [
        NSColor.white.withAlphaComponent(0.10).cgColor,
        NSColor.white.withAlphaComponent(0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: body.midX, y: body.maxY),
                           end: CGPoint(x: body.midX, y: body.midY), options: [])

    // ---- The page -----------------------------------------------------------
    let pw = S * 0.42, ph = S * 0.54
    let page = CGRect(x: S * 0.29, y: S * 0.23, width: pw, height: ph)
    let fold = S * 0.115                       // folded top-right corner

    let pagePath = CGMutablePath()
    pagePath.move(to: CGPoint(x: page.minX, y: page.minY))
    pagePath.addLine(to: CGPoint(x: page.maxX, y: page.minY))
    pagePath.addLine(to: CGPoint(x: page.maxX, y: page.maxY - fold))
    pagePath.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY))
    pagePath.addLine(to: CGPoint(x: page.minX, y: page.maxY))
    pagePath.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.040,
                  color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(pagePath)
    ctx.setFillColor(NSColor(srgbRed: 0.97, green: 0.97, blue: 0.95, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Fold shadow triangle.
    ctx.move(to: CGPoint(x: page.maxX - fold, y: page.maxY))
    ctx.addLine(to: CGPoint(x: page.maxX, y: page.maxY - fold))
    ctx.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY - fold))
    ctx.closePath()
    ctx.setFillColor(NSColor(srgbRed: 0.78, green: 0.80, blue: 0.76, alpha: 1).cgColor)
    ctx.fillPath()

    // Faint text lines.
    ctx.setFillColor(NSColor(srgbRed: 0.72, green: 0.75, blue: 0.72, alpha: 1).cgColor)
    let lineX = page.minX + pw * 0.14
    var lineY = page.maxY - ph * 0.24
    for i in 0..<5 {
        let lw = pw * (i == 4 ? 0.42 : 0.72)
        ctx.fill(CGRect(x: lineX, y: lineY, width: lw, height: S * 0.018))
        lineY -= ph * 0.145
    }

    // ---- The bay leaf -------------------------------------------------------
    // Drawn along its own axis then rotated across the page's lower-right corner.
    ctx.saveGState()
    ctx.translateBy(x: S * 0.615, y: S * 0.315)
    ctx.rotate(by: -.pi * 0.23)

    let L = S * 0.34, Wd = S * 0.135
    let leaf = CGMutablePath()
    leaf.move(to: CGPoint(x: -L / 2, y: 0))
    leaf.addQuadCurve(to: CGPoint(x: L / 2, y: 0), control: CGPoint(x: 0, y: Wd))
    leaf.addQuadCurve(to: CGPoint(x: -L / 2, y: 0), control: CGPoint(x: 0, y: -Wd))
    leaf.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.010), blur: S * 0.030,
                  color: NSColor.black.withAlphaComponent(0.50).cgColor)
    ctx.addPath(leaf)
    let leafGrad = CGGradient(colorsSpace: space, colors: [
        NSColor(srgbRed: 0.22, green: 0.82, blue: 0.50, alpha: 1).cgColor,
        NSColor(srgbRed: 0.55, green: 0.93, blue: 0.60, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.clip()
    ctx.drawLinearGradient(leafGrad, start: CGPoint(x: -L / 2, y: -Wd),
                           end: CGPoint(x: L / 2, y: Wd), options: [])
    ctx.restoreGState()

    // Midrib + stem.
    ctx.setStrokeColor(NSColor(srgbRed: 0.06, green: 0.35, blue: 0.20, alpha: 0.85).cgColor)
    ctx.setLineWidth(S * 0.014)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: -L / 2 - S * 0.045, y: 0))
    ctx.addLine(to: CGPoint(x: L / 2 - S * 0.02, y: 0))
    ctx.strokePath()
    ctx.restoreGState()

    ctx.restoreGState()   // tile clip
    return ctx.makeImage()!
}

// ---- Write the iconset ------------------------------------------------------
let sizes: [(name: String, px: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = root.appendingPathComponent("dist/AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (name, px) in sizes {
    let image = makeIcon(px)
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: px, height: px)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: iconset.appendingPathComponent("\(name).png"))
}
print("wrote \(iconset.path)")
