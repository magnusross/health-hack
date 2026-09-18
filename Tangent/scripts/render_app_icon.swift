import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let canvas = 1024
let svgW: CGFloat = 513.38
let svgH: CGFloat = 557.27
let scale = min(CGFloat(canvas) / svgW, CGFloat(canvas) / svgH)
let originX = (CGFloat(canvas) - svgW * scale) / 2
let originY = (CGFloat(canvas) - svgH * scale) / 2

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: canvas,
    height: canvas,
    bitsPerComponent: 8,
    bytesPerRow: canvas * 4,
    space: colorSpace,
    bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
) else {
    fputs("Unable to create bitmap context\n", stderr)
    exit(1)
}

ctx.setFillColor(CGColor(red: 121.0 / 255.0, green: 127.0 / 255.0, blue: 242.0 / 255.0, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
ctx.translateBy(x: 0, y: CGFloat(canvas))
ctx.scaleBy(x: 1, y: -1)
ctx.translateBy(x: originX, y: originY)
ctx.scaleBy(x: scale, y: scale)

ctx.setFillColor(CGColor(red: 242.0 / 255.0, green: 242.0 / 255.0, blue: 247.0 / 255.0, alpha: 1))
let circles: [(CGFloat, CGFloat, CGFloat)] = [
    (348.76, 387.89, 34.96),
    (261.74, 148.31, 34.96),
    (391.23, 241.96, 34.96),
    (134.08, 241.96, 34.96),
    (174.93, 387.89, 34.96),
    (183.25, 173.81, 26.22),
    (207.07, 106.72, 17.48),
    (261.74, 89.24, 8.74),
    (341.50, 174.54, 26.22),
    (412.69, 173.98, 17.48),
    (447.82, 219.37, 8.74),
    (393.23, 317.36, 26.22),
    (418.10, 384.07, 17.48),
    (387.46, 432.60, 8.74),
    (261.74, 419.66, 26.22),
    (203.75, 460.96, 17.48),
    (148.94, 443.92, 8.74),
    (129.20, 317.36, 26.22),
    (74.31, 272.03, 17.48),
    (76.58, 214.68, 8.74),
]
for (cx, cy, r) in circles {
    ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
}

guard let image = ctx.makeImage() else {
    fputs("Unable to create image\n", stderr)
    exit(1)
}

guard let destination = CGImageDestinationCreateWithURL(
    output as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fputs("Unable to create PNG destination\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, image, [kCGImagePropertyHasAlpha: false] as CFDictionary)
guard CGImageDestinationFinalize(destination) else {
    fputs("Unable to write PNG\n", stderr)
    exit(1)
}

print("Wrote \(output.path)")
