import AppKit

// A deterministic native SF Symbol icon; generated assets stay in .build.
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(calibratedRed: 0.16, green: 0.23, blue: 0.28, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: pixels, height: pixels), xRadius: CGFloat(pixels) * 0.22, yRadius: CGFloat(pixels) * 0.22).fill()
        let symbol = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(paletteColors: [.white]))!
        let inset = CGFloat(pixels) * 0.18
        symbol.draw(in: NSRect(x: inset, y: inset, width: CGFloat(pixels) - inset * 2, height: CGFloat(pixels) - inset * 2))
        NSGraphicsContext.restoreGraphicsState()
        let png = bitmap.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
