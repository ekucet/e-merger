#!/usr/bin/env swift
// Created by Mr. t.
//
// Draws the app icon: Mergino, an absurd creature that is a yellow "lanes merge" road
// sign with cross-eyes, a moustache and sneakers. The merging lane is his arm, and it
// holds an espresso. Writes every size of AppIcon.appiconset at its exact pixel size.
// Usage: swift scripts/generate_icon.swift

import AppKit
import CoreGraphics

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let ink = rgb(0x141414)
let white = rgb(0xFFFFFF)

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

func circle(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: CGColor) {
    ctx.setFillColor(color)
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Fills `path` with a black outline, the way every cartoon part here is drawn.
func outlined(_ ctx: CGContext, _ path: CGPath, fill: CGColor, line: CGFloat = 8) {
    ctx.addPath(path)
    ctx.setFillColor(fill)
    ctx.fillPath()
    ctx.addPath(path)
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(line)
    ctx.setLineJoin(.round)
    ctx.strokePath()
}

func stroke(_ ctx: CGContext, width: CGFloat, color: CGColor, cap: CGLineCap = .round, _ build: (CGContext) -> Void) {
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(cap)
    build(ctx)
    ctx.strokePath()
}

func cloud(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat) {
    circle(ctx, x + 18 * s, y - 6 * s, 30 * s, white)
    circle(ctx, x + 56 * s, y - 22 * s, 42 * s, white)
    circle(ctx, x + 96 * s, y - 4 * s, 28 * s, white)
    ctx.addPath(rounded(CGRect(x: x - 22 * s, y: y - 8 * s, width: 156 * s, height: 40 * s), 20 * s))
    ctx.setFillColor(white)
    ctx.fillPath()
}

/// A rounded diamond around (cx, cy) with half-diagonal `r`.
func diamond(cx: CGFloat, cy: CGFloat, r: CGFloat, corner: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let top = CGPoint(x: cx, y: cy - r), right = CGPoint(x: cx + r, y: cy)
    let bottom = CGPoint(x: cx, y: cy + r), left = CGPoint(x: cx - r, y: cy)
    path.move(to: CGPoint(x: (top.x + left.x) / 2, y: (top.y + left.y) / 2))
    path.addArc(tangent1End: top, tangent2End: right, radius: corner)
    path.addArc(tangent1End: right, tangent2End: bottom, radius: corner)
    path.addArc(tangent1End: bottom, tangent2End: left, radius: corner)
    path.addArc(tangent1End: left, tangent2End: top, radius: corner)
    path.closeSubpath()
    return path
}

func shoe(_ ctx: CGContext, x: CGFloat, y: CGFloat, facing: CGFloat) {
    // Upper, sole, laces.
    let upper = CGMutablePath()
    upper.move(to: CGPoint(x: x - facing * 30, y: y - 40))
    upper.addLine(to: CGPoint(x: x + facing * 16, y: y - 40))
    upper.addQuadCurve(to: CGPoint(x: x + facing * 86, y: y), control: CGPoint(x: x + facing * 34, y: y - 8))
    upper.addLine(to: CGPoint(x: x - facing * 36, y: y))
    upper.closeSubpath()
    outlined(ctx, upper, fill: rgb(0xE5322D))
    outlined(ctx, rounded(CGRect(x: min(x - facing * 42, x + facing * 92), y: y - 4, width: 134, height: 22), 11), fill: white, line: 7)
    stroke(ctx, width: 7, color: white) { c in
        c.move(to: CGPoint(x: x + facing * 6, y: y - 30))
        c.addLine(to: CGPoint(x: x + facing * 22, y: y - 22))
        c.move(to: CGPoint(x: x + facing * 22, y: y - 34))
        c.addLine(to: CGPoint(x: x + facing * 36, y: y - 22))
    }
}

/// Draws in a 1024 × 1024 space with the origin at the top left.
func draw(_ ctx: CGContext) {
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = rounded(tile, 186)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: rgb(0x0B1E3D, 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(0x2E8BF0))
    ctx.fillPath()
    ctx.restoreGState()

    // Sky, clouds, and a tricolore floor to stand on.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([rgb(0x1E6FE8), rgb(0x56C4FB)], [0, 1]),
        start: CGPoint(x: 512, y: 100),
        end: CGPoint(x: 512, y: 830),
        options: []
    )
    cloud(ctx, 150, 250, 1.0)
    cloud(ctx, 760, 190, 0.8)
    let floorY: CGFloat = 826
    ctx.setFillColor(rgb(0x1F9D55))
    ctx.fill(CGRect(x: 100, y: floorY, width: 275, height: 110))
    ctx.setFillColor(white)
    ctx.fill(CGRect(x: 375, y: floorY, width: 274, height: 110))
    ctx.setFillColor(rgb(0xE5322D))
    ctx.fill(CGRect(x: 649, y: floorY, width: 275, height: 110))
    ctx.restoreGState()

    let cx: CGFloat = 512, cy: CGFloat = 448

    // Legs and sneakers, straight on the floor.
    stroke(ctx, width: 28, color: ink, cap: .butt) { c in
        c.move(to: CGPoint(x: 438, y: 660))
        c.addLine(to: CGPoint(x: 438, y: 830))
        c.move(to: CGPoint(x: 586, y: 660))
        c.addLine(to: CGPoint(x: 586, y: 830))
    }
    shoe(ctx, x: 432, y: 858, facing: -1)
    shoe(ctx, x: 592, y: 858, facing: 1)

    // Everything above the knees leans, for attitude.
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy)
    ctx.rotate(by: -4 * .pi / 180)
    ctx.translateBy(x: -cx, y: -cy)

    // Left arm, up and gesturing behind the sign: the pinched fingers.
    stroke(ctx, width: 26, color: ink) { c in
        c.move(to: CGPoint(x: 330, y: 540))
        c.addQuadCurve(to: CGPoint(x: 212, y: 450), control: CGPoint(x: 220, y: 560))
    }
    let handX: CGFloat = 206, handY: CGFloat = 416
    for (dx, spread) in [(-22, -10), (0, 0), (22, 10)] as [(CGFloat, CGFloat)] {
        let finger = CGMutablePath()
        finger.move(to: CGPoint(x: handX + dx, y: handY + 20))
        finger.addQuadCurve(to: CGPoint(x: handX + spread * 0.3, y: handY - 58), control: CGPoint(x: handX + dx + spread * 1.4, y: handY - 26))
        stroke(ctx, width: 34, color: ink) { $0.addPath(finger) }
        stroke(ctx, width: 20, color: white) { $0.addPath(finger) }
    }
    outlined(ctx, CGPath(ellipseIn: CGRect(x: handX - 38, y: handY - 8, width: 76, height: 66), transform: nil), fill: white)

    // The sign itself.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 20, color: rgb(0x0B1E3D, 0.40))
    ctx.addPath(diamond(cx: cx, cy: cy, r: 292, corner: 34))
    ctx.setFillColor(rgb(0xFFD60A))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(diamond(cx: cx, cy: cy, r: 292, corner: 34))
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([rgb(0xFFE545), rgb(0xFBC500)], [0, 1]),
        start: CGPoint(x: cx, y: cy - 292),
        end: CGPoint(x: cx, y: cy + 292),
        options: []
    )
    ctx.resetClip()
    ctx.addPath(diamond(cx: cx, cy: cy, r: 266, corner: 26))
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(11)
    ctx.strokePath()

    // The merging lane leaves the sign and becomes an arm.
    stroke(ctx, width: 62, color: ink, cap: .round) { c in
        c.move(to: CGPoint(x: 568, y: 470))
        c.addCurve(to: CGPoint(x: 748, y: 610), control1: CGPoint(x: 610, y: 560), control2: CGPoint(x: 680, y: 610))
    }

    // Arrow: head + stem.
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 512, y: 214))
    arrow.addLine(to: CGPoint(x: 648, y: 396))
    arrow.addQuadCurve(to: CGPoint(x: 632, y: 412), control: CGPoint(x: 654, y: 416))
    arrow.addLine(to: CGPoint(x: 578, y: 402))
    arrow.addLine(to: CGPoint(x: 578, y: 655))
    arrow.addLine(to: CGPoint(x: 446, y: 655))
    arrow.addLine(to: CGPoint(x: 446, y: 402))
    arrow.addLine(to: CGPoint(x: 392, y: 412))
    arrow.addQuadCurve(to: CGPoint(x: 376, y: 396), control: CGPoint(x: 370, y: 416))
    arrow.closeSubpath()
    ctx.addPath(arrow)
    ctx.setFillColor(ink)
    ctx.fillPath()

    // Googly, proudly misaligned eyes.
    circle(ctx, 468, 356, 47, white)
    circle(ctx, 562, 348, 38, white)
    circle(ctx, 486, 368, 21, ink)
    circle(ctx, 546, 338, 17, ink)
    circle(ctx, 493, 361, 6, white)
    circle(ctx, 551, 332, 5, white)

    // Grin with the tongue hanging out.
    let mouth = CGMutablePath()
    mouth.move(to: CGPoint(x: 462, y: 490))
    mouth.addLine(to: CGPoint(x: 562, y: 490))
    mouth.addCurve(to: CGPoint(x: 462, y: 490), control1: CGPoint(x: 562, y: 586), control2: CGPoint(x: 462, y: 586))
    mouth.closeSubpath()
    ctx.addPath(mouth)
    ctx.setFillColor(white)
    ctx.fillPath()
    let tongue = rounded(CGRect(x: 492, y: 528, width: 50, height: 82), 25)
    ctx.addPath(tongue)
    ctx.setFillColor(rgb(0xFF5E8A))
    ctx.fillPath()
    stroke(ctx, width: 5, color: rgb(0xC9305F)) { c in
        c.move(to: CGPoint(x: 517, y: 548))
        c.addLine(to: CGPoint(x: 517, y: 590))
    }

    // Handlebar moustache under the arrowhead, tips curling up past the stem.
    for side: CGFloat in [-1, 1] {
        let tache = CGMutablePath()
        tache.move(to: CGPoint(x: 512, y: 446))
        tache.addCurve(to: CGPoint(x: 512 + side * 148, y: 424),
                       control1: CGPoint(x: 512 + side * 50, y: 418),
                       control2: CGPoint(x: 512 + side * 110, y: 482))
        tache.addCurve(to: CGPoint(x: 512, y: 500),
                       control1: CGPoint(x: 512 + side * 142, y: 500),
                       control2: CGPoint(x: 512 + side * 56, y: 522))
        tache.closeSubpath()
        outlined(ctx, tache, fill: white, line: 7)
    }

    // The espresso.
    stroke(ctx, width: 9, color: rgb(0xFFFFFF, 0.95)) { c in
        c.move(to: CGPoint(x: 764, y: 520))
        c.addCurve(to: CGPoint(x: 776, y: 452), control1: CGPoint(x: 738, y: 496), control2: CGPoint(x: 800, y: 480))
        c.move(to: CGPoint(x: 802, y: 520))
        c.addCurve(to: CGPoint(x: 814, y: 460), control1: CGPoint(x: 778, y: 496), control2: CGPoint(x: 838, y: 486))
    }
    let handle = CGPath(ellipseIn: CGRect(x: 826, y: 544, width: 38, height: 38), transform: nil)
    ctx.addPath(handle)
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(22)
    ctx.strokePath()
    ctx.addPath(handle)
    ctx.setStrokeColor(white)
    ctx.setLineWidth(9)
    ctx.strokePath()
    let cup = CGMutablePath()
    cup.move(to: CGPoint(x: 736, y: 530))
    cup.addLine(to: CGPoint(x: 846, y: 530))
    cup.addCurve(to: CGPoint(x: 736, y: 530), control1: CGPoint(x: 846, y: 628), control2: CGPoint(x: 736, y: 628))
    cup.closeSubpath()
    outlined(ctx, cup, fill: white)
    ctx.setFillColor(rgb(0x5B2E12))
    ctx.fillEllipse(in: CGRect(x: 748, y: 525, width: 86, height: 14))
    outlined(ctx, rounded(CGRect(x: 716, y: 606, width: 150, height: 20), 10), fill: white, line: 7)

    ctx.restoreGState()
}

let output = URL(fileURLWithPath: "EMerger/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let scale = CGFloat(size) / 1024
    ctx.scaleBy(x: scale, y: -scale)
    ctx.translateBy(x: 0, y: -1024)
    draw(ctx)
    let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    try! png.write(to: output.appendingPathComponent("icon_\(size).png"))
}
print("Wrote AppIcon.appiconset")
