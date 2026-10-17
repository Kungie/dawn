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
    var opacity: Double = 0.22
    var body: some View {
        Canvas { ctx, size in
            var y = 0.0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y + 2, width: size.width, height: 1)), with: .color(.black.opacity(opacity)))
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
    /// An 18 pt template image: half a sun on a horizon with two cuts.
    /// Claude Code waiting: a ringed dot top right. Claude finished: a solid dot top right.
    static func image(asking: Bool, done: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            // Same proportions as the website's menu bar: a horizon bar, a small gap, then a half sun.
            NSRect(x: 2.5, y: 3.6, width: 13, height: 1.3).fill()
            let sun = NSBezierPath()
            sun.appendArc(withCenter: NSPoint(x: 9, y: 5.6), radius: 5.8, startAngle: 0, endAngle: 180)
            sun.close()
            sun.fill()
            // Two thin cuts through the sun; with the gap above the horizon it reads as a stack of bars.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSRect(x: 0, y: 7.3, width: 18, height: 0.7).fill()
            NSRect(x: 0, y: 9.3, width: 18, height: 0.7).fill()
            if asking || done {
                // Knock out a gap around the mark so it reads against the sun.
                NSBezierPath(ovalIn: NSRect(x: 11.2, y: 9.2, width: 7.6, height: 7.6)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                if asking {
                    let ring = NSBezierPath(ovalIn: NSRect(x: 12.2, y: 10.2, width: 5.6, height: 5.6))
                    ring.lineWidth = 1.2
                    ring.stroke()
                    NSBezierPath(ovalIn: NSRect(x: 14.0, y: 12.0, width: 2.0, height: 2.0)).fill()
                } else {
                    NSBezierPath(ovalIn: NSRect(x: 12.4, y: 10.4, width: 5.2, height: 5.2)).fill()
                }
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    /// The countdown next to the sun: Space Grotesk Medium with tabular figures, like the website's menu bar.
    /// Falls back to the system font.
    static func title(_ text: String) -> NSAttributedString {
        let system = NSFont.menuBarFont(ofSize: 0).pointSize
        let size = system + 1
        let base = CTFontDescriptorCreateWithNameAndSize("SpaceGrotesk-Light" as CFString, size)
        let attrs: [CFString: Any] = [
            kCTFontVariationAttribute: [NSNumber(value: 0x7767_6874): NSNumber(value: 500)], // wght 500
            kCTFontFeatureSettingsAttribute: [[kCTFontOpenTypeFeatureTag: "tnum", kCTFontOpenTypeFeatureValue: 1]],
        ]
        let ct = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateCopyWithAttributes(base, attrs as CFDictionary), size, nil)
        if (CTFontCopyFamilyName(ct) as String).hasPrefix("Space Grotesk") {
            return NSAttributedString(string: text, attributes: [.font: ct as NSFont])
        }
        return NSAttributedString(string: text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: system, weight: .regular)])
    }
}

// MARK: - Panel design (Claude Design, October 2026)

/// The small header chip: red square, cream border, a V of a cream and a sand triangle cut by thin red lines.
struct DawnChip: View {
    var size: CGFloat = 22
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 24
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let frame = Path(CGRect(x: 1.25 * s, y: 1.25 * s, width: 21.5 * s, height: 21.5 * s))
            ctx.fill(frame, with: .color(Ident.red))
            ctx.stroke(frame, with: .color(Ident.cream), lineWidth: 2.5 * s)
            var left = Path(); left.addLines([p(5.5, 5.5), p(9.6, 5.5), p(12, 12.6), p(12, 18.5)]); left.closeSubpath()
            var right = Path(); right.addLines([p(18.5, 5.5), p(14.4, 5.5), p(12, 12.6), p(12, 18.5)]); right.closeSubpath()
            ctx.fill(left, with: .color(Ident.cream))
            ctx.fill(right, with: .color(Ident.sand))
            for y in [6.45, 7.89, 9.34, 10.78, 12.23, 13.67, 15.11, 16.56] {
                ctx.fill(Path(CGRect(x: 4 * s, y: y * s, width: 16 * s, height: 0.5 * s)), with: .color(Ident.red))
            }
        }
        .frame(width: size, height: size)
    }
}

/// "DAWN" in Archivo expanded with the stacked black and red cut-out shadow.
struct Wordmark: View {
    var text = "DAWN"
    var size: CGFloat = 17
    var body: some View {
        let t = Text(text).font(Fonts.archivo(size)).tracking(size * 0.01)
        ZStack {
            t.foregroundColor(Ident.redDeep).offset(y: 4)
            t.foregroundColor(Ident.black).offset(y: 3)
            t.foregroundColor(Ident.red).offset(y: 2)
            t.foregroundColor(Ident.black).offset(y: 1)
            t.foregroundColor(Ident.cream)
        }
        .padding(.bottom, 4)
    }
}

/// Dawn's sun (viewBox 100 × 50): a red half-disc on the bottom edge, cut by black bands that thicken downwards.
/// `rise` 1 = fully up, 0 = sunk by half its height (the "next ping" state).
struct DawnSun: View {
    var rise: Double = 1
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 100
            let drop = (1 - rise) * 26 * s
            ctx.clip(to: Path(CGRect(origin: .zero, size: sz)))
            // A full disc centred on the bottom edge; the frame clips it to the upper half.
            let sun = Path(ellipseIn: CGRect(x: 8 * s, y: 8 * s + drop, width: 84 * s, height: 84 * s))
            ctx.fill(sun, with: .color(Ident.red))
            ctx.clip(to: sun)
            // Risen: four bands. Low on the horizon: the two thin ones from the design.
            let cuts: [(Double, Double)] = rise > 0.5 ? [(27, 1.6), (34, 2.6), (40, 3.4), (44.5, 3.8)] : [(38, 1.4), (44, 2.4)]
            for (y, h) in cuts {
                ctx.fill(Path(CGRect(x: 0, y: y * s, width: sz.width, height: h * s)), with: .color(Ident.black))
            }
        }
        .aspectRatio(2, contentMode: .fit)
    }
}

/// The 36 × 20 square switch from the design.
struct DawnSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Rectangle().fill(isOn ? Ident.red : Ident.line)
                Rectangle().fill(isOn ? Ident.cream : Ident.dim).frame(width: 16, height: 16).padding(2)
            }
            .frame(width: 36, height: 20)
            .animation(.easeOut(duration: 0.15), value: isOn)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

/// The big red action with a hard red-deep shadow under it.
struct DawnPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Fonts.archivo(13, weight: 900))
            .tracking(0.52)
            .textCase(.uppercase)
            .foregroundColor(Ident.cream)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(ZStack {
                Rectangle().fill(Ident.redDeep).offset(y: configuration.isPressed ? 1 : 3)
                Rectangle().fill(Ident.red)
            })
            .offset(y: configuration.isPressed ? 2 : 0)
            .padding(.bottom, 3)
            .contentShape(Rectangle())
    }
}

/// Plain text actions: "Settings", "Quit", "I started in Claude.ai".
struct DawnTextButtonStyle: ButtonStyle {
    var color: Color = Ident.cream2
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Fonts.grotesk(13, weight: 500))
            .foregroundColor(configuration.isPressed ? Ident.cream : color)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Space Mono bold uppercase label, the design's section caption.
    func dawnLabel(_ color: Color = Ident.dim) -> some View {
        self.font(Fonts.mono(11, bold: true)).tracking(1.1).textCase(.uppercase).foregroundColor(color)
    }
}
