import AppKit
import SwiftUI

/// Colors and controls modelled on Minecraft Bedrock's own menus: slate
/// buttons that look raised, a dark outline, and a bevelled green Play button.
enum Theme {
    static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    static let background = rgb(0x1E2229)
    static let bar = rgb(0x14171C)
    static let outline = rgb(0x0B0D10)
    static let card = rgb(0x14171C).opacity(0.92)
    static let field = rgb(0x111318)
    static let text = Color.white
    static let dimText = rgb(0x9AA4B2)
    static let errorText = rgb(0xFF8A80)
    static let warningText = rgb(0xFFD180)

    static let slate = (face: rgb(0x2D333C), edge: rgb(0x1A1E24), light: rgb(0x3A414C))
    static let slateOn = (face: rgb(0x4A5260), edge: rgb(0x2F353E), light: rgb(0x5C6575))
    static let green = (face: rgb(0x3C8527), edge: rgb(0x2A5E1B), light: rgb(0x63A944))
    static let red = (face: rgb(0x8E2E2E), edge: rgb(0x5E1B1B), light: rgb(0xB04545))

    /// A pixel icon from the app's resources, drawn without smoothing.
    static func icon(_ name: String) -> Image {
        if let image = Bundle.module.image(forResource: name) {
            return Image(nsImage: image).interpolation(.none)
        }
        return Image(systemName: "questionmark.square")
    }

    static let heading = Font.system(size: 13, weight: .heavy)
}

/// A raised block button: a face, a lighter top edge, a darker bottom edge
/// and a dark outline. Pressing it pushes the face down onto the edge.
struct ChunkyButtonStyle: ButtonStyle {
    enum Kind { case slate, selected, green, red }
    var kind: Kind = .slate
    var fontSize: CGFloat = 12
    var horizontalPadding: CGFloat = 16
    var verticalPadding: CGFloat = 9
    /// Stretch to the width of the container, with the label on the left.
    var fullWidth = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let colors: (face: Color, edge: Color, light: Color) = switch kind {
        case .slate: Theme.slate
        case .selected: Theme.slateOn
        case .green: Theme.green
        case .red: Theme.red
        }
        let pressed = configuration.isPressed
        let edge: CGFloat = pressed ? 2 : 5
        return configuration.label
            .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
            .font(.system(size: fontSize, weight: .heavy))
            .kerning(0.5)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(colors.face)
            .overlay(alignment: .top) { Rectangle().fill(colors.light).frame(height: 2) }
            .padding(.bottom, edge)
            .background(colors.edge)
            .overlay(Rectangle().stroke(Theme.outline, lineWidth: 2))
            .offset(y: pressed ? 3 : 0)
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// Bedrock's switch: a square knob that slides along a chunky track, which
/// turns green when on. The label sits on the left, the switch on the right.
struct BlockToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) { configuration.isOn.toggle() }
        } label: {
            HStack {
                configuration.label
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 16)
                track(on: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func track(on: Bool) -> some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Rectangle()
                .fill(on ? Theme.green.face : Theme.field)
                .frame(width: 56, height: 28)
                .overlay(alignment: .leading) {
                    // A tick on the green side, a ring on the off side, as in the game.
                    Image(systemName: on ? "checkmark" : "circle")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(on ? Theme.text : Theme.dimText)
                        .frame(width: 28)
                        .offset(x: on ? 0 : 28)
                }
            Rectangle()
                .fill(Theme.slate.light)
                .frame(width: 24, height: 20)
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.35)).frame(height: 2) }
                .padding(.bottom, 4)
                .background(Theme.slate.edge)
                .overlay(Rectangle().stroke(Theme.outline, lineWidth: 2))
                .padding(2)
        }
        .overlay(Rectangle().stroke(Theme.outline, lineWidth: 2))
    }
}

/// A dark panel with an outline, for cards and lists on top of the scenery.
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .background(Theme.card)
            .overlay(Rectangle().stroke(Theme.outline, lineWidth: 2))
    }
}

/// Small chunky tabs inside a page, for example General and About in Settings.
struct SubTabs: View {
    let titles: [String]
    @Binding var selected: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(titles.indices, id: \.self) { i in
                Button(titles[i].uppercased()) { selected = i }
                    .buttonStyle(ChunkyButtonStyle(kind: i == selected ? .selected : .slate, fontSize: 11))
            }
        }
    }
}

/// A section heading inside a page.
struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(Theme.heading).kerning(0.6).foregroundStyle(Theme.text)
    }
}

/// The block-world scenery behind the Play page. Falls back to the small
/// pixel-art scene when the large image is missing.
struct Scenery: View {
    var body: some View {
        if let image = Bundle.module.image(forResource: "scene-hd") {
            Image(nsImage: image)
                .interpolation(.high)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let image = Bundle.module.image(forResource: "scene") {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(colors: [Theme.rgb(0x7DB7E8), Theme.rgb(0x5B8F43)], startPoint: .top, endPoint: .bottom)
        }
    }
}
