import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        _ = layout(proposal: proposal, subviews: subviews, bounds: bounds)
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews, bounds: CGRect? = nil) -> (size: CGSize, positions: [CGPoint]) {
        let leadingX = bounds?.minX ?? 0
        // Placing must break lines exactly where measuring did. The bounds come back as the measured
        // width rounded to the pixel grid, a hair narrower at times, which pushed the last word of a
        // full line onto a new one the measured height had no room for. Break against the width
        // that was offered, with half a point of slack.
        let trailingX: CGFloat
        if let width = proposal.width {
            trailingX = leadingX + max(width, bounds?.width ?? 0) + 0.5
        } else {
            trailingX = bounds.map { $0.maxX + 0.5 } ?? .infinity
        }
        var currentX: CGFloat = leadingX
        var currentY: CGFloat = bounds?.minY ?? 0
        var lineHeight: CGFloat = 0
        var contentMaxX: CGFloat = leadingX
        var positions: [CGPoint] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > trailingX && currentX > leadingX {
                currentX = leadingX
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            if let _ = bounds {
                subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            contentMaxX = max(contentMaxX, currentX - spacing)
        }

        return (
            CGSize(
                width: max(contentMaxX - leadingX, 0),
                height: currentY - (bounds?.minY ?? 0) + lineHeight
            ),
            positions
        )
    }
}
