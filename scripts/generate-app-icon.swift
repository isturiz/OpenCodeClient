#!/usr/bin/env swift
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct Palette {
    let backgroundTop: NSColor
    let backgroundBottom: NSColor
    let panelTop: NSColor
    let panelBottom: NSColor
    let border: NSColor
    let symbol: NSColor
    let shadow: NSColor
}

private let palettes: [(filename: String, palette: Palette)] = [
    (
        "AppIcon.png",
        Palette(
            backgroundTop: color(0xF8FAF7),
            backgroundBottom: color(0xDDEFE6),
            panelTop: color(0x17231C),
            panelBottom: color(0x09100C),
            border: color(0x2F4C3C),
            symbol: color(0x68DBA1),
            shadow: color(0x07110B, alpha: 0.28)
        )
    ),
    (
        "AppIcon-Dark.png",
        Palette(
            backgroundTop: color(0x16251C),
            backgroundBottom: color(0x030504),
            panelTop: color(0x111A14),
            panelBottom: color(0x070A08),
            border: color(0x294536),
            symbol: color(0x78E8B2),
            shadow: color(0x000000, alpha: 0.62)
        )
    ),
    (
        "AppIcon-Tinted.png",
        Palette(
            backgroundTop: color(0x303030),
            backgroundBottom: color(0x080808),
            panelTop: color(0x242424),
            panelBottom: color(0x0C0C0C),
            border: color(0x555555),
            symbol: color(0xFFFFFF),
            shadow: color(0x000000, alpha: 0.65)
        )
    ),
]

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: generate-app-icon.swift <appiconset-directory>\n".utf8))
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for variant in palettes {
    let data = try renderIcon(using: variant.palette)
    try data.write(to: outputDirectory.appendingPathComponent(variant.filename), options: .atomic)
}

private func renderIcon(using palette: Palette) throws -> Data {
    let size = NSSize(width: 1_024, height: 1_024)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
        let bitmapContext = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
    else {
        throw IconError.couldNotCreateBitmap
    }
    let context = NSGraphicsContext(cgContext: bitmapContext, flipped: false)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let canvas = NSRect(origin: .zero, size: size)
    gradient(from: palette.backgroundBottom, to: palette.backgroundTop).draw(in: canvas, angle: 58)

    let panelRect = NSRect(x: 112, y: 112, width: 800, height: 800)
    let panel = NSBezierPath(roundedRect: panelRect, xRadius: 218, yRadius: 218)
    let shadow = NSShadow()
    shadow.shadowColor = palette.shadow
    shadow.shadowBlurRadius = 48
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()
    palette.panelBottom.setFill()
    panel.fill()

    NSGraphicsContext.saveGraphicsState()
    panel.addClip()
    gradient(from: palette.panelBottom, to: palette.panelTop).draw(in: panelRect, angle: 62)
    NSGraphicsContext.restoreGraphicsState()

    palette.border.setStroke()
    panel.lineWidth = 10
    panel.stroke()

    drawChevron(color: palette.symbol)
    drawVoiceBars(color: palette.symbol)

    NSGraphicsContext.restoreGraphicsState()
    guard let image = bitmapContext.makeImage() else {
        throw IconError.couldNotEncodePNG
    }
    let data = NSMutableData()
    guard
        let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        throw IconError.couldNotEncodePNG
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw IconError.couldNotEncodePNG
    }
    return data as Data
}

private func drawChevron(color: NSColor) {
    let chevron = NSBezierPath()
    chevron.move(to: NSPoint(x: 292, y: 646))
    chevron.line(to: NSPoint(x: 426, y: 512))
    chevron.line(to: NSPoint(x: 292, y: 378))
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    chevron.lineWidth = 66
    color.setStroke()
    chevron.stroke()
}

private func drawVoiceBars(color: NSColor) {
    let bars: [(x: CGFloat, height: CGFloat)] = [
        (500, 178),
        (584, 306),
        (668, 388),
        (752, 238),
    ]
    color.setFill()
    for bar in bars {
        let rect = NSRect(x: bar.x, y: 512 - bar.height / 2, width: 42, height: bar.height)
        NSBezierPath(roundedRect: rect, xRadius: 21, yRadius: 21).fill()
    }
}

private func gradient(from start: NSColor, to end: NSColor) -> NSGradient {
    guard let value = NSGradient(starting: start, ending: end) else {
        preconditionFailure("The icon color space must support gradients")
    }
    return value
}

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

private enum IconError: Error {
    case couldNotCreateBitmap
    case couldNotEncodePNG
}
