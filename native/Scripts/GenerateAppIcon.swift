#!/usr/bin/env swift

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: GenerateAppIcon.swift <source.svg> <output.png>\n".utf8))
    exit(64)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let pixelSize = 1024

guard let source = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write(Data("Could not load \(sourceURL.path)\n".utf8))
    exit(65)
}

guard
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
    let bitmap = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: pixelSize * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )
else {
    FileHandle.standardError.write(Data("Could not allocate the app icon bitmap\n".utf8))
    exit(70)
}

let graphicsContext = NSGraphicsContext(cgContext: bitmap, flipped: false)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
graphicsContext.imageInterpolation = .high

let canvas = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
bitmap.setFillColor(red: 1, green: 253 / 255, blue: 248 / 255, alpha: 1)
bitmap.fill(canvas)
source.draw(in: canvas, from: .zero, operation: .sourceOver, fraction: 1)

graphicsContext.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let image = bitmap.makeImage() else {
    FileHandle.standardError.write(Data("Could not finish the app icon bitmap\n".utf8))
    exit(70)
}

let png = NSMutableData()
guard let destination = CGImageDestinationCreateWithData(
    png,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    FileHandle.standardError.write(Data("Could not encode the app icon PNG\n".utf8))
    exit(70)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("Could not finish encoding the app icon PNG\n".utf8))
    exit(70)
}

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try (png as Data).write(to: outputURL, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("Could not write \(outputURL.path): \(error)\n".utf8))
    exit(74)
}
