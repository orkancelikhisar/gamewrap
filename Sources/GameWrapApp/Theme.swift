import SwiftUI

enum FieldStyle {
    static let paper = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let ink = Color.primary
    static let muted = Color.secondary
    static let orange = Color.accentColor
    static let line = Color(nsColor: .separatorColor)
}

struct FieldButton: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(primary ? Color.white : FieldStyle.ink)
            .background(primary ? Color.accentColor : FieldStyle.panel,
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(FieldStyle.line, lineWidth: 0.5))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
    }
}

struct FieldCaption: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
    }
}

// Small native pixel animation, paused for accessibility and inactive windows.
struct PixelController: View {
    var highlighted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let pixels = [
        "   XXXXXXXXXXXX   ",
        "  XXXXXXXXXXXXXX  ",
        " XXXXXXXXXXXXXXXX ",
        "XXXXOXXXXXXXOXXXXX",
        "XXXOOOXXXXXOXOXXXX",
        "XXXXOXXXXXXXOXXXXX",
        "XXXXXXXXXXXXXXXXXX",
        "XXXXXX      XXXXXX",
        " XXXX        XXXX "
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30,
                                paused: reduceMotion || scenePhase != .active)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { (context: inout GraphicsContext, size: CGSize) in
                let cell: CGFloat = 5
                let originX: CGFloat = (size.width - 90) / 2
                let originY: CGFloat = 14 + CGFloat(reduceMotion ? 0 : sin(time * 1.5) * 3)
                let origin = CGPoint(x: originX, y: originY)
                for (row, line) in pixels.enumerated() {
                    for (column, pixel) in line.enumerated() where pixel != " " {
                        let rect = CGRect(x: origin.x + CGFloat(column) * cell,
                                          y: origin.y + CGFloat(row) * cell,
                                          width: cell + 0.5, height: cell + 0.5)
                        context.fill(Path(rect), with: .color(pixel == "O" ? FieldStyle.paper :
                            (highlighted ? FieldStyle.orange : FieldStyle.ink)))
                    }
                }
                for index in 0..<8 {
                    let angle = Double(index) * .pi / 4
                    let drift = reduceMotion ? 0 : sin(time * 1.2 + angle) * 4
                    let x: CGFloat = size.width / 2 + CGFloat(cos(angle) * (75 + drift))
                    let y: CGFloat = size.height / 2 + CGFloat(sin(angle) * (25 + drift))
                    let opacity = reduceMotion ? 0.5 : 0.35 + (sin(time + angle) + 1) * 0.2
                    context.fill(Path(CGRect(x: x, y: y, width: 4, height: 4)),
                                 with: .color(FieldStyle.orange.opacity(opacity)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
