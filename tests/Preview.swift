import AppKit

@main
struct Preview {
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let snapshot = try JSONDecoder().decode(QuotaSnapshot.self, from: data)
        let controller = OverlayController()
        controller.snapshot = snapshot
        controller.strip.controller = controller
        controller.panel.contentView = controller.strip
        for (name, appearanceName, background) in [
            ("light", NSAppearance.Name.aqua, NSColor.white),
            ("dark", NSAppearance.Name.darkAqua, NSColor(calibratedWhite: 0.12, alpha: 1))
        ] {
            controller.strip.appearance = NSAppearance(named: appearanceName)
            let size = NSSize(width: controller.strip.preferredWidth(maximum: 560), height: 32)
            controller.panel.setContentSize(size)
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: 64,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            background.setFill()
            NSRect(origin: .zero, size: size).fill()
            controller.strip.appearance!.performAsCurrentDrawingAppearance {
                controller.strip.draw(controller.strip.bounds)
            }
            NSGraphicsContext.restoreGraphicsState()
            let png = bitmap.representation(using: .png, properties: [:])!
            let output = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("preview-\(name).png")
            try png.write(to: output)
            print(output.path)
        }
    }
}
