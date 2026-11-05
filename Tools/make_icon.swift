// Renders the GlassCount app icon (1024x1024 master). Usage: swift Tools/make_icon.swift out.png
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let S = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }

// macOS icon grid: 824pt rounded square centred in 1024, radius ≈ 22.5 %.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Soft drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: c(0, 0, 0, 0.35))
ctx.addPath(tilePath); ctx.setFillColor(c(0.2, 0.2, 0.4)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
// Background: deep indigo → violet → warm coral.
let bg = CGGradient(colorsSpace: cs, colors: [c(0.10, 0.12, 0.38), c(0.42, 0.22, 0.62), c(0.98, 0.50, 0.42)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 150, y: 920), end: CGPoint(x: 880, y: 120), options: [])
// Glow blobs.
let glow = CGGradient(colorsSpace: cs, colors: [c(0.45, 0.80, 1.0, 0.55), c(0.45, 0.80, 1.0, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 780), startRadius: 0, endCenter: CGPoint(x: 330, y: 780), endRadius: 420, options: [])
let glow2 = CGGradient(colorsSpace: cs, colors: [c(1.0, 0.75, 0.45, 0.50), c(1.0, 0.75, 0.45, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow2, startCenter: CGPoint(x: 760, y: 220), startRadius: 0, endCenter: CGPoint(x: 760, y: 220), endRadius: 420, options: [])

// Glass disc.
let centre = CGPoint(x: 512, y: 512)
let disc = CGPath(ellipseIn: CGRect(x: centre.x - 270, y: centre.y - 270, width: 540, height: 540), transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: c(0, 0, 0, 0.30))
ctx.addPath(disc); ctx.setFillColor(c(1, 1, 1, 0.20)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState(); ctx.addPath(disc); ctx.clip()
let sheen = CGGradient(colorsSpace: cs, colors: [c(1, 1, 1, 0.55), c(1, 1, 1, 0.08)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 330, y: 790), end: CGPoint(x: 700, y: 240), options: [])
ctx.restoreGState()
ctx.addPath(disc); ctx.setStrokeColor(c(1, 1, 1, 0.65)); ctx.setLineWidth(5); ctx.strokePath()

// Track ring + progress arc (about 70 % elapsed), round caps.
let ringR: CGFloat = 200
ctx.setLineCap(.round)
ctx.setLineWidth(46); ctx.setStrokeColor(c(1, 1, 1, 0.28))
ctx.addArc(center: centre, radius: ringR, startAngle: 0, endAngle: .pi * 2, clockwise: false); ctx.strokePath()
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 18, color: c(1, 1, 1, 0.7))
ctx.setStrokeColor(c(1, 1, 1, 0.98)); ctx.setLineWidth(46)
let start = CGFloat.pi / 2, sweep = CGFloat.pi * 2 * 0.70
ctx.addArc(center: centre, radius: ringR, startAngle: start, endAngle: start - sweep, clockwise: true); ctx.strokePath()
ctx.restoreGState()

// Centre dot (clock hub) and a short hand pointing at the arc end.
ctx.setFillColor(c(1, 1, 1, 0.95))
ctx.fillEllipse(in: CGRect(x: centre.x - 26, y: centre.y - 26, width: 52, height: 52))
ctx.setLineWidth(26); ctx.setStrokeColor(c(1, 1, 1, 0.95))
ctx.move(to: centre); ctx.addLine(to: CGPoint(x: centre.x, y: centre.y + 120)); ctx.strokePath()
ctx.restoreGState()

// Top edge highlight on the tile.
ctx.saveGState(); ctx.addPath(tilePath); ctx.setLineWidth(4)
ctx.replacePathWithStrokedPath(); ctx.clip()
let edge = CGGradient(colorsSpace: cs, colors: [c(1, 1, 1, 0.6), c(1, 1, 1, 0.0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(edge, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 500), options: [])
ctx.restoreGState()

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest))
