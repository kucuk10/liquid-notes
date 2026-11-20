import SwiftUI

/// Draws a notebook paper pattern. Spacing is defined in page points, so patterns scale with the page.
struct PaperBackground: View {
    let style: PaperStyle
    let pageSize: CGSize

    /// Line spacing in points (about a wide-ruled 8.5 mm).
    private let ruleSpacing: CGFloat = 24
    private let gridSpacing: CGFloat = 18
    private let topMargin: CGFloat = 72

    var body: some View {
        Canvas { context, size in
            let scale = size.width / pageSize.width
            let lineColor = Color(red: 0.55, green: 0.68, blue: 0.85).opacity(0.55)
            let lineWidth = max(0.5, 0.75 * scale)

            switch style {
            case .blank:
                break

            case .ruled:
                var lines = Path()
                var y = topMargin
                while y < pageSize.height - ruleSpacing / 2 {
                    lines.move(to: CGPoint(x: 0, y: y * scale))
                    lines.addLine(to: CGPoint(x: size.width, y: y * scale))
                    y += ruleSpacing
                }
                context.stroke(lines, with: .color(lineColor), lineWidth: lineWidth)

                // Left margin line, like a school notebook.
                var margin = Path()
                margin.move(to: CGPoint(x: 64 * scale, y: 0))
                margin.addLine(to: CGPoint(x: 64 * scale, y: size.height))
                context.stroke(margin, with: .color(.red.opacity(0.35)), lineWidth: lineWidth)

            case .grid:
                var grid = Path()
                var x = gridSpacing
                while x < pageSize.width {
                    grid.move(to: CGPoint(x: x * scale, y: 0))
                    grid.addLine(to: CGPoint(x: x * scale, y: size.height))
                    x += gridSpacing
                }
                var y = gridSpacing
                while y < pageSize.height {
                    grid.move(to: CGPoint(x: 0, y: y * scale))
                    grid.addLine(to: CGPoint(x: size.width, y: y * scale))
                    y += gridSpacing
                }
                context.stroke(grid, with: .color(lineColor.opacity(0.7)), lineWidth: lineWidth)

            case .dotted:
                let radius = max(0.75, 1.1 * scale)
                var dots = Path()
                var y = gridSpacing
                while y < pageSize.height {
                    var x = gridSpacing
                    while x < pageSize.width {
                        dots.addEllipse(in: CGRect(
                            x: x * scale - radius, y: y * scale - radius,
                            width: radius * 2, height: radius * 2
                        ))
                        x += gridSpacing
                    }
                    y += gridSpacing
                }
                context.fill(dots, with: .color(.gray.opacity(0.45)))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        ForEach(PaperStyle.allCases) { style in
            PaperBackground(style: style, pageSize: PaperSize.letter.size)
                .background(.white)
                .aspectRatio(612 / 792, contentMode: .fit)
        }
    }
    .padding()
}
