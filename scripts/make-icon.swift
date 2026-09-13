import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                          isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: factor)
        transform.concat()
        let tile = NSBezierPath(roundedRect: CGRect(x: 48, y: 48, width: 928, height: 928), xRadius: 210, yRadius: 210)
        NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.65, blue: 0.57, alpha: 1),
                   ending: NSColor(calibratedRed: 0.025, green: 0.30, blue: 0.30, alpha: 1))!.draw(in: tile, angle: -65)
        let symbol = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil)!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.white]))!
        let symbolRect = CGRect(x: 222, y: 222, width: 580, height: 580)
        symbol.draw(in: symbolRect)
        let dot = NSBezierPath(ovalIn: CGRect(x: 404, y: 404, width: 216, height: 216))
        NSColor(calibratedRed: 1, green: 0.32, blue: 0.32, alpha: 1).setFill()
        dot.fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}