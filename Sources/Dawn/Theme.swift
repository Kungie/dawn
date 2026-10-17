import AppKit
import CoreText
import SwiftUI

/// The Vektor Labs "Ident" palette: red, cream and an almost-black.
enum Ident {
    static let black = Color(hex: 0x050303)
    static let black2 = Color(hex: 0x0E0908)
    static let line = Color(hex: 0x2A1B19)
    static let cream = Color(hex: 0xF3E9D6)
    static let cream2 = Color(hex: 0xE6D9BE)
    static let sand = Color(hex: 0xD2C09B)
    static let red = Color(hex: 0xE2231A)
    static let redDeep = Color(hex: 0x8F0F0B)
    static let dim = Color(hex: 0xA09189)
    static let ok = Color(hex: 0x7FD49A)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Fonts ship inside the app (Resources/Fonts, SIL Open Font License) and are registered for this process only.
/// Every accessor falls back to a system font, so a build without the fonts still looks reasonable.
enum Fonts {
    static func register() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for file in files where ["woff2", "ttf", "otf"].contains(file.pathExtension) {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }

    private static let wght = 0x7767_6874 // 'wght'
    private static let wdth = 0x7764_7468 // 'wdth'

    private static func variable(_ name: String, family: String, size: CGFloat, axes: [Int: CGFloat]) -> CTFont? {
        let base = CTFontDescriptorCreateWithNameAndSize(name as CFString, size)
        let attrs = [kCTFontVariationAttribute: axes.reduce(into: [NSNumber: NSNumber]()) { $0[NSNumber(value: $1.key)] = NSNumber(value: Double($1.value)) }]
        let font = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateCopyWithAttributes(base, attrs as CFDictionary), size, nil)
        return (CTFontCopyFamilyName(font) as String).hasPrefix(family) ? font : nil
    }

    /// Archivo at 125 % width: the big cut-out headline type of the Ident site.
    static func archivo(_ size: CGFloat, weight: CGFloat = 900) -> Font {
        if let f = variable("ArchivoRoman-Regular", family: "Archivo", size: size, axes: [wdth: 125, wght: weight]) { return Font(f) }
        return .system(size: size, weight: .black).width(.expanded)
    }

    /// VT323: the pixel face of Dawn's screen.
    static func vt(_ size: CGFloat) -> Font {
        NSFont(name: "VT323-Regular", size: size) != nil ? .custom("VT323-Regular", size: size) : .system(size: size * 0.8, design: .monospaced)
    }

    /// Space Grotesk for body text.
    static func grotesk(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        if let f = variable("SpaceGrotesk-Light", family: "Space Grotesk", size: size, axes: [wght: weight]) { return Font(f) }
        return .system(size: size)
    }

    /// Space Mono for small technical labels.
    static func mono(_ size: CGFloat, bold: Bool = false) -> Font {
        let name = bold ? "SpaceMono-Bold" : "SpaceMono-Regular"
        return NSFont(name: name, size: size) != nil ? .custom(name, size: size) : .system(size: size, design: .monospaced)
    }
}

/// The striped V of Vektor Labs, drawn from the same geometry as the website's `#vmark` symbol (viewBox 0 0 100 100).
struct StripedV: View {
    var left: Color = Ident.cream
    var right: Color = Ident.sand

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 100
            for i in 0..<9 {
                let y = 10 + Double(i) * 8.95
                let l = 12 + Double(i) * 2.685
                let r = 66 - Double(i) * 2.685
                ctx.fill(Self.stripe(x: l, y: y, skew: 1.92, s: s), with: .color(left))
                ctx.fill(Self.stripe(x: r, y: y, skew: -1.92, s: s), with: .color(right))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private static func stripe(x: Double, y: Double, skew: Double, s: Double) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x * s, y: y * s))
        p.addLine(to: CGPoint(x: (x + 22) * s, y: y * s))
        p.addLine(to: CGPoint(x: (x + 22 + skew) * s, y: (y + 6.4) * s))
        p.addLine(to: CGPoint(x: (x + skew) * s, y: (y + 6.4) * s))
        p.closeSubpath()
        return p
    }
}

/// The red chip with a cream border and the V inside, as in the site header.
struct IdentChip: View {
    var size: CGFloat = 26
    var body: some View {
        ZStack {
            Rectangle().fill(Ident.red)
            StripedV().padding(size * 0.12)
        }
        .frame(width: size * 1.15, height: size)
        .overlay(Rectangle().strokeBorder(Ident.cream, lineWidth: max(2, size * 0.14)))
    }
}

/// A striped sun on a horizon: thicker black cuts toward the bottom, like the sunrise on the site.
struct StripedSun: View {
    var rise: Double = 0.75
    var color: Color = Ident.red

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let r = min(w * 0.36, h * 0.9)
            let cy = h + r * 0.35 - rise * (r * 1.05)
            ctx.clip(to: Path(CGRect(x: 0, y: 0, width: w, height: h - 3)))
            ctx.fill(Path(ellipseIn: CGRect(x: w / 2 - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(color))
            for c in 0..<6 {
                let y = cy - r * 0.05 + Double(c) * r * 0.16
                ctx.fill(Path(CGRect(x: 0, y: y, width: w, height: 1.2 + Double(c) * r * 0.025)), with: .color(Ident.black))
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Ident.cream).frame(height: 3) }
    }
}

/// CRT scanlines over the screen card.
struct Scanlines: View {
    var body: some View {
        Canvas { ctx, size in
            var y = 0.0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y + 2, width: size.width, height: 1)), with: .color(.black.opacity(0.22)))
                y += 3
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Controls

struct RedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Fonts.archivo(11.5, weight: 800))
            .foregroundColor(Ident.cream)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? Ident.redDeep : Ident.red)
            .contentShape(Rectangle())
    }
}

struct GhostButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Fonts.grotesk(compact ? 11 : 12, weight: 500))
            .foregroundColor(Ident.cream)
            .padding(.horizontal, compact ? 8 : 12).padding(.vertical, compact ? 4 : 7)
            .background(configuration.isPressed ? Ident.line : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Ident.cream.opacity(0.85), lineWidth: 1.2))
            .contentShape(Rectangle())
    }
}

/// A flat red/black switch that renders the same in the app and in snapshots.
struct IdentToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 10) {
                configuration.label
                Spacer(minLength: 6)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Rectangle().fill(configuration.isOn ? Ident.red : Ident.line).frame(width: 30, height: 15)
                    Rectangle().fill(Ident.cream).frame(width: 11, height: 11).padding(2)
                }
                .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Menu bar icon

enum MenuBarIcon {
    /// An 18 pt template image: half a sun on a horizon with two cuts, and a dot when Claude Code is asking.
    static func image(asking: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.setFill()
            let horizon = NSRect(x: 1, y: 3, width: 16, height: 1.6)
            horizon.fill()
            let sun = NSBezierPath()
            sun.appendArc(withCenter: NSPoint(x: 9, y: 5.4), radius: 7, startAngle: 0, endAngle: 180)
            sun.close()
            sun.fill()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSRect(x: 0, y: 6.6, width: 18, height: 1.0).fill()
            NSRect(x: 0, y: 9.2, width: 18, height: 0.8).fill()
            if asking {
                NSBezierPath(ovalIn: NSRect(x: 11.2, y: 9.2, width: 7.6, height: 7.6)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSBezierPath(ovalIn: NSRect(x: 12.4, y: 10.4, width: 5.2, height: 5.2)).fill()
            }
            _ = rect
            return true
        }
        img.isTemplate = true
        return img
    }
}
