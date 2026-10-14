import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Keep the approved artwork intact; generated iconset files stay in .build.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Icon generation failed: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 3 else {
    fail("Usage: swift build-icon.swift <source-logo.png> <destination.iconset>")
}
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
      CGImageSourceGetType(imageSource) as String? == UTType.png.identifier,
      let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    fail("The source logo must be a readable PNG image.")
}
guard image.width == 1024, image.height == 1024 else {
    fail("The source logo must be 1024 × 1024 pixels.")
}
guard let colorSpace = image.colorSpace, colorSpace.model == .rgb else {
    fail("The source logo must use an RGB color space.")
}

do {
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = size * scale
            let suffix = scale == 2 ? "@2x" : ""
            let output = destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
            if pixels == 1024 {
                // Preserve the full-size artwork and PNG metadata byte for byte.
                try Data(contentsOf: source).write(to: output, options: .atomic)
                continue
            }
            guard let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                bytesPerRow: pixels * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { fail("Could not create the \(pixels)-pixel transparent drawing context.") }
            let bounds = CGRect(x: 0, y: 0, width: pixels, height: pixels)
            context.clear(bounds)
            context.interpolationQuality = .high
            context.draw(image, in: bounds)
            guard let resized = context.makeImage(),
                  let encoder = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                fail("Could not create the \(pixels)-pixel PNG output.")
            }
            CGImageDestinationAddImage(encoder, resized, nil)
            guard CGImageDestinationFinalize(encoder) else {
                fail("Could not write the \(pixels)-pixel PNG output.")
            }
        }
    }
} catch {
    fail("\(error.localizedDescription)")
}
