import AppKit
let destination = CommandLine.arguments[1]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        NSColor(calibratedRed: 0.13, green: 0.18, blue: 0.24, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.05, y: p * 0.05, width: p * 0.9, height: p * 0.9), xRadius: p * 0.19, yRadius: p * 0.19).fill()
        let text = ">_" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: p * 0.49, weight: .bold), .foregroundColor: NSColor(calibratedRed: 0.45, green: 0.9, blue: 0.73, alpha: 1)]
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (p - textSize.width) / 2, y: (p - textSize.height) / 2), withAttributes: attributes)
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = bitmap.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: URL(fileURLWithPath: "\(destination)/icon_\(size)x\(size)\(suffix).png"))
    }
}
