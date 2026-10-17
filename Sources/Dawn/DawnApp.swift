import AppKit
import SwiftUI

enum DawnInfo {
    static let version = "0.1.0"
}

struct DawnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = DawnModel.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in DawnModel.shared.start() }
    }
}

/// `Dawn snapshot <folder>` renders the panel with demo data, for the README.
enum Snapshot {
    @MainActor
    static func run(to folder: String) {
        let dir = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let shots: [(String, DawnModel, Bool)] = [
            ("panel", DawnModel.demoModel(), true),
            ("panel-asking", DawnModel.demoModel(asking: true), false),
            ("panel-idle", DawnModel.demoModel(idle: true), false),
        ]
        for (name, model, setup) in shots {
            model.showSetup = setup
            let renderer = ImageRenderer(content: PanelView(model: model))
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("could not render \(name)"); continue
            }
            try? png.write(to: dir.appendingPathComponent("\(name).png"))
            print("wrote \(name).png")
        }
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
