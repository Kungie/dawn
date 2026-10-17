import AppKit
import SwiftUI

enum DawnInfo {
    static let version = "0.2.3"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusPanel: StatusPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            statusPanel = StatusPanelController(model: DawnModel.shared)
            DawnModel.shared.start()
            if ProcessInfo.processInfo.environment["DAWN_PANEL_SELFTEST"] == "1" { statusPanel?.selfTest() }
        }
    }
}

/// `Dawn snapshot <folder>` renders the panel with demo data, for the README.
enum Snapshot {
    @MainActor
    static func run(to folder: String) {
        let dir = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let shots: [(String, DawnModel, CGFloat)] = [
            ("panel", DawnModel.demoModel(), PanelView.width / 2),
            ("panel-asking", DawnModel.demoModel(asking: true), PanelView.width / 2),
            ("panel-idle", DawnModel.demoModel(idle: true), PanelView.width / 2),
            ("panel-settings", DawnModel.demoModel(settings: true), PanelView.width / 2),
            // As in the menu bar near the screen's right edge: panel pushed left, notch off-centre.
            ("panel-right", DawnModel.demoModel(), 262),
        ]
        for (name, model, arrowX) in shots {
            let geometry = PanelGeometry()
            geometry.arrowX = arrowX
            let renderer = ImageRenderer(content: PanelContainer(model: model, geometry: geometry))
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("could not render \(name)"); continue
            }
            try? png.write(to: dir.appendingPathComponent("\(name).png"))
            print("wrote \(name).png")
        }
        menuBar(to: dir.appendingPathComponent("menubar.png").path)
        print("wrote menubar.png")
    }

    /// A strip of dark menu bar with Dawn's item at 2x: sun plus countdown, as macOS draws it in dark mode.
    @MainActor
    static func menuBar(to path: String) {
        let scale: CGFloat = 2
        let title = NSMutableAttributedString(attributedString: MenuBarIcon.title(" 1:44"))
        title.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: title.length))
        let textSize = title.size()
        let size = NSSize(width: 18 + textSize.width + 20, height: 24)
        let image = NSImage(size: NSSize(width: size.width * scale, height: size.height * scale), flipped: false) { _ in
            NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
            NSColor(white: 0.12, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            let icon = MenuBarIcon.image(asking: false)
            let tinted = NSImage(size: icon.size, flipped: false) { r in
                icon.draw(in: r)
                NSColor.white.set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: 10, y: 3, width: 18, height: 18))
            title.draw(at: NSPoint(x: 28, y: (size.height - textSize.height) / 2))
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    /// The app icon: a striped red sun rising over a cream horizon on black glass.
    @MainActor
    static func icon(to path: String) {
        let art = ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous).fill(
                RadialGradient(colors: [Color(hex: 0x2A0D0A), Ident.black], center: .init(x: 0.5, y: 0.62), startRadius: 10, endRadius: 560))
            Canvas { ctx, size in
                // Sun centred on the horizon, cut by black bands that thicken toward the bottom, as on the site.
                let horizon = size.height * 0.68, r = size.width * 0.32, cx = size.width / 2
                ctx.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)))
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: horizon - r, width: r * 2, height: r * 2)), with: .color(Ident.red))
                for c in 0..<5 {
                    let y = horizon - r * 0.58 + Double(c) * r * 0.13
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: r * (0.03 + Double(c) * 0.014))), with: .color(Ident.black))
                }
            }
            .frame(width: 824, height: 824)
            Rectangle().fill(Ident.cream).frame(width: 560, height: 16).offset(y: 824 * 0.18 + 8)
            Scanlines().clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous)).opacity(0.6)
            RoundedRectangle(cornerRadius: 185, style: .continuous).strokeBorder(Ident.line, lineWidth: 6)
        }
        .frame(width: 824, height: 824)
        .frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: art)
        renderer.scale = 1
        guard let tiff = renderer.nsImage?.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
