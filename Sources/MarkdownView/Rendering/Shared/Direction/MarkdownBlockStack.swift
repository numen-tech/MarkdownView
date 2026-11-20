//
//  MarkdownBlockStack.swift
//  MarkdownView (numen-tech fork)
//

import SwiftUI

/// numen fork (gemma4-qat#1765): a column of blocks, each laid out in its own content direction
/// (`MarkdownNodeView.direction`). It is a leading-aligned `VStack` until a block's direction
/// differs from the stack's layout direction; from then on that block sits against the far edge,
/// where its own reading starts, and the stack still hugs its widest block, so a reply bubble does
/// not grow to the full width for one right-to-left paragraph. `AnyLayout` keeps every block's
/// identity when the first such block streams in.
struct MarkdownBlockStack: View {
    var blocks: [MarkdownNodeView]
    var spacing: CGFloat

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let farSide = blocks.map { block in block.direction.map { $0 != layoutDirection } ?? false }
        let layout = farSide.contains(true)
            ? AnyLayout(MarkdownBlockStackLayout(spacing: spacing, farSide: farSide))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
        layout {
            ForEach(blocks.indices, id: \.self) { index in
                blocks[index]
            }
        }
    }
}

/// The far-side placement of `MarkdownBlockStack`. A layout's placements mirror in a
/// right-to-left environment, so `minX` is the leading edge in both directions.
struct MarkdownBlockStackLayout: Layout {
    var spacing: CGFloat
    /// Per subview: whether it sits against the trailing edge.
    var farSide: [Bool]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)).width }.max() ?? 0
        // Heights at the width the blocks are placed at, so the stack reserves what it places.
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let height = heights.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let trailing = index < farSide.count && farSide[index]
            let x = trailing ? bounds.maxX - size.width : bounds.minX
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: size.width, height: size.height))
            y += size.height + spacing
        }
    }
}
