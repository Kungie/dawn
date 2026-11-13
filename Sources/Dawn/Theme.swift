import AppKit
import CoreText
import SwiftUI

/// Binder's look: dark only, mostly black and white. Colour is small (a dot, an icon, a 2 px bar) and always
/// means something. Dawn keeps its red for its own mark: the sun, the running window's bar and the one
/// main action.
enum Look {
    static let bg = Color(hex: 0x0B0B0C)
    static let panel = Color(hex: 0x141416)
    static let card = Color(hex: 0x1C1C1F)
    static let raised = Color(hex: 0x242428)
    static let line = Color(hex: 0x26262A)
    static let lineStrong = Color(hex: 0x34343A)
    static let text = Color(hex: 0xEDEDED)
    static let text2 = Color(hex: 0xA1A1A1)
    static let text3 = Color(hex: 0x6B6B6B)

    /// Dawn's sun.
    static let red = Color(hex: 0xE2231A)
    static let progress = Color(hex: 0xF2C94C)
    static let done = Color(hex: 0x8B7CF6)
    static let attention = Color(hex: 0xF2994A)
    static let bad = Color(hex: 0xEB5757)
    static let ok = Color(hex: 0x4CB782)
    static let todo = Color(hex: 0xD4D4D4)

    /// Corner radii: controls and cards / panels.
    static let control: CGFloat = 8
    static let radius: CGFloat = 10
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Inter for text and Geist Mono for numbers, ids and paths, weights 400 and 500 only. They ship inside the
/// app (Resources/Fonts, SIL Open Font License) and are registered for this process; every accessor falls
/// back to the system font.
enum Fonts {
    static func register() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for file in files where ["woff2", "ttf", "otf"].contains(file.pathExtension) {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }

    static func text(_ size: CGFloat = 13, medium: Bool = false) -> Font {
        let name = medium ? "Inter-Medium" : "Inter-Regular"
        return NSFont(name: name, size: size) != nil ? .custom(name, size: size) : .system(size: size, weight: medium ? .medium : .regular)
    }

    static func mono(_ size: CGFloat = 12, medium: Bool = false) -> Font {
        let name = medium ? "GeistMono-Medium" : "GeistMono-Regular"
        return NSFont(name: name, size: size) != nil
            ? .custom(name, size: size)
            : .system(size: size, weight: medium ? .medium : .regular, design: .monospaced)
    }
}

// MARK: - Dawn's mark

/// Dawn's mark: a red sun whose lower part is cut into three strips by horizontal gaps, like a sunrise.
/// The gaps are transparent, so it sits on any background.
enum DawnMark {
    /// Gaps as (top, bottom) in fractions of the diameter, from the top.
    static let gaps: [(CGFloat, CGFloat)] = [(0.555, 0.615), (0.705, 0.76), (0.85, 0.9)]
}

struct DawnLogo: View {
    var color: Color = Look.red
    /// Dims the mark when there's no window running.
    var lit = true

    var body: some View {
        Canvas { ctx, size in
            let d = min(size.width, size.height)
            let box = CGRect(x: (size.width - d) / 2, y: (size.height - d) / 2, width: d, height: d)
            ctx.drawLayer { layer in
                layer.fill(Path(ellipseIn: box), with: .color(color))
                layer.blendMode = .clear
                for (top, bottom) in DawnMark.gaps {
                    layer.fill(Path(CGRect(x: box.minX, y: box.minY + top * d, width: d, height: (bottom - top) * d)), with: .color(.black))
                }
            }
        }
        .opacity(lit ? 1 : 0.45)
        .aspectRatio(1, contentMode: .fit)
    }
}

/// A laptop seen from the side with its lid up: a flat base and the lid at an angle from the hinge.
/// Keep awake's icon, in Dawn's red on a small card tile; dimmed while it's off.
struct LidIcon: View {
    var on = false

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 16
            let t = 2.2 * s // bar thickness
            // Base: a flat bar along the bottom.
            ctx.fill(Path(roundedRect: CGRect(x: 1 * s, y: 12.4 * s, width: 14 * s, height: t), cornerRadius: t / 2),
                     with: .color(Look.red))
            // Lid: as long as the base, hinged just above its left end and opened to 45 degrees.
            var lid = ctx
            lid.translateBy(x: 2.2 * s, y: 11.0 * s)
            lid.rotate(by: .degrees(-45))
            lid.fill(Path(roundedRect: CGRect(x: 0, y: -t / 2, width: 14 * s, height: t), cornerRadius: t / 2),
                     with: .color(Look.red))
        }
        .frame(width: 18, height: 18)
        .opacity(on ? 1 : 0.55)
        .frame(width: 30, height: 30)
        .background(RoundedRectangle(cornerRadius: Look.control, style: .continuous).fill(Look.card))
        .overlay(RoundedRectangle(cornerRadius: Look.control, style: .continuous).strokeBorder(Look.line, lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: on)
    }
}

// MARK: - Controls

/// A small pill switch. On is light, off is a raised track: colour is kept for things that mean something.
struct DawnSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Look.text : Look.raised)
                    .overlay(Capsule().strokeBorder(isOn ? Color.clear : Look.lineStrong, lineWidth: 1))
                Circle().fill(isOn ? Look.bg : Look.text2).frame(width: 12, height: 12).padding(3)
            }
            .frame(width: 30, height: 18)
            .animation(.easeOut(duration: 0.15), value: isOn)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .accessibilityValue(isOn ? "on" : "off")
    }
}

/// A segmented control: a card with a hairline, the chosen option on a raised fill.
struct DawnSegmented<Option: Hashable & CaseIterable>: View where Option.AllCases: RandomAccessCollection, Option: Labelled {
    @Binding var selection: Option
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(Option.allCases), id: \.self) { option in
                let on = option == selection
                Button { selection = option } label: {
                    Text(option.label)
                        .font(Fonts.text(12, medium: on))
                        .foregroundColor(on ? Look.text : Look.text3)
                        .frame(minWidth: 44, minHeight: 22)
                        .padding(.horizontal, 4)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Look.raised : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: Look.control, style: .continuous).fill(Look.card))
        .overlay(RoundedRectangle(cornerRadius: Look.control, style: .continuous).strokeBorder(Look.line, lineWidth: 1))
        .animation(.easeOut(duration: 0.12), value: selection)
    }
}

protocol Labelled { var label: String { get } }
extension MenuBarShows: Labelled {}

/// A small button: card fill, hairline border, 8 px corners.
struct ControlButtonStyle: ButtonStyle {
    var compact = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Fonts.text(12, medium: true))
            .foregroundColor(Look.text)
            .padding(.horizontal, compact ? 10 : 12)
            .frame(height: compact ? 24 : 28)
            .background(RoundedRectangle(cornerRadius: Look.control, style: .continuous)
                .fill(configuration.isPressed ? Look.raised : Look.card))
            .overlay(RoundedRectangle(cornerRadius: Look.control, style: .continuous).strokeBorder(Look.lineStrong, lineWidth: 1))
            .contentShape(Rectangle())
            .pointerCursor()
    }
}

/// The one main action, in Dawn's red.
struct DawnPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Fonts.text(13, medium: true))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(RoundedRectangle(cornerRadius: Look.control, style: .continuous).fill(Look.red))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
            .pointerCursor()
    }
}

/// Plain text actions: "Settings", "Quit", "I started in Claude.ai".
struct DawnTextButtonStyle: ButtonStyle {
    var color: Color = Look.text2
    var hoverColor: Color = Look.text
    func makeBody(configuration: Configuration) -> some View {
        HoverText(label: configuration.label, pressed: configuration.isPressed, color: color, hoverColor: hoverColor)
    }
}

final class HoverBox: ObservableObject {
    @Published var on = false
}

/// Text action that answers the mouse: on hover it brightens and gets a thin red underline, and the cursor
/// turns into a pointing hand.
struct HoverText<Label: View>: View {
    let label: Label
    let pressed: Bool
    let color: Color
    let hoverColor: Color
    @StateObject private var hover = HoverBox()

    var body: some View {
        let active = hover.on || pressed
        label
            .font(Fonts.text(13))
            .foregroundColor(active ? hoverColor : color)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Look.red).frame(height: 1).offset(y: 3).opacity(active ? 1 : 0)
            }
            .opacity(pressed ? 0.75 : 1)
            .contentShape(Rectangle())
            .onHover { hover.on = $0 }
            .animation(.easeOut(duration: 0.12), value: active)
            .pointerCursor()
    }
}

/// A 24 px pill: card fill, hairline border, an optional dot, 12 px text.
struct Chip: View {
    let text: String
    var dot: Color?
    var body: some View {
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
            Text(text).font(Fonts.text(12)).foregroundColor(Look.text2).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(Look.card))
        .overlay(Capsule().strokeBorder(Look.line, lineWidth: 1))
    }
}

/// A status dot: colour that means something.
struct Dot: View {
    let color: Color
    var size: CGFloat = 6
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

extension View {
    /// The pointing-hand cursor while the mouse is over this view.
    func pointerCursor() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    /// A small caption over a group: 12 px, the third text colour, sentence case.
    func caption(_ color: Color = Look.text3) -> some View {
        self.font(Fonts.text(12)).foregroundColor(color)
    }

    /// A card or panel surface: fill, hairline border, 10 px corners.
    func surface(_ fill: Color = Look.card) -> some View {
        self.background(RoundedRectangle(cornerRadius: Look.radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: Look.radius, style: .continuous).strokeBorder(Look.line, lineWidth: 1))
    }
}

// MARK: - Menu bar icon

enum MenuBarIcon {
    /// An 18 pt template image of Dawn's mark.
    /// Claude Code waiting: a ringed dot top right. Claude finished: a solid dot top right.
    static func image(asking: Bool, done: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            // Dawn's mark: a 13 pt sun with three gaps across its lower part.
            let d: CGFloat = 13, x: CGFloat = 2.5, y: CGFloat = 2.5
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: d, height: d)).fill()
            NSGraphicsContext.current?.compositingOperation = .clear
            for (top, bottom) in DawnMark.gaps {
                // The image isn't flipped: fractions from the top become heights from the bottom.
                NSRect(x: x, y: y + d - bottom * d, width: d, height: max(1, (bottom - top) * d)).fill()
            }
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            if asking || done {
                // Knock out a gap around the mark so it reads against the sun.
                NSGraphicsContext.current?.compositingOperation = .clear
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

    /// The text next to the sun: Inter Medium with tabular figures, falling back to the system font.
    static func title(_ text: String) -> NSAttributedString {
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        let base = CTFontDescriptorCreateWithNameAndSize("Inter-Medium" as CFString, size)
        let attrs: [CFString: Any] = [
            kCTFontFeatureSettingsAttribute: [[kCTFontOpenTypeFeatureTag: "tnum", kCTFontOpenTypeFeatureValue: 1]],
        ]
        let ct = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateCopyWithAttributes(base, attrs as CFDictionary), size, nil)
        if (CTFontCopyFamilyName(ct) as String).hasPrefix("Inter") {
            return NSAttributedString(string: text, attributes: [.font: ct as NSFont])
        }
        return NSAttributedString(string: text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)])
    }
}
