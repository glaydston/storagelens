import SwiftUI
import StorageLensKit

struct CapacitySegment: Identifiable, Equatable {
    let id: String
    let label: String
    let size: Int64
    let color: Color
    /// Free space is drawn as the track: outlined rather than filled.
    var isTrack = false
}

/// The volume's capacity as one stacked bar, the way System Settings shows it.
///
/// Segments are separated by a 2 pt surface gap and the whole bar has rounded
/// ends, so a thin slice still reads as its own block. Every segment is named
/// in the legend below — color is never the only cue.
struct CapacityBar: View {
    let segments: [CapacitySegment]
    var height: CGFloat = 22

    private static let gap: CGFloat = 2
    private static let minimumWidth: CGFloat = 5
    private static let radius: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let widths = widths(in: geometry.size.width)
            HStack(spacing: Self.gap) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    shape(at: index)
                        .fill(segment.isTrack ? AnyShapeStyle(segment.color.opacity(0.55))
                                              : AnyShapeStyle(segment.color.gradient))
                        .frame(width: widths[index])
                        .help(L("%@ — %@", segment.label, ByteFormat.string(segment.size)))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            segments
                .map { "\($0.label) \(ByteFormat.string($0.size))" }
                .joined(separator: ", ")
        )
    }

    /// Round only the two outer ends; interior edges stay square so adjacent
    /// segments read as one continuous bar.
    private func shape(at index: Int) -> UnevenRoundedRectangle {
        let leading = index == 0 ? Self.radius : 0
        let trailing = index == segments.count - 1 ? Self.radius : 0
        return UnevenRoundedRectangle(
            topLeadingRadius: leading,
            bottomLeadingRadius: leading,
            bottomTrailingRadius: trailing,
            topTrailingRadius: trailing
        )
    }

    /// Proportional widths, with a floor so a sliver stays visible, then scaled
    /// back down if the floors and gaps overflow the available width.
    private func widths(in available: CGFloat) -> [CGFloat] {
        let total = segments.reduce(Int64(0)) { $0 + max(0, $1.size) }
        let gaps = Self.gap * CGFloat(max(0, segments.count - 1))
        let usable = max(0, available - gaps)
        guard total > 0, usable > 0 else {
            return Array(repeating: usable / CGFloat(max(1, segments.count)), count: segments.count)
        }

        var widths = segments.map { segment -> CGFloat in
            let raw = usable * CGFloat(max(0, segment.size)) / CGFloat(total)
            return segment.size > 0 ? max(Self.minimumWidth, raw) : 0
        }

        let overflow = widths.reduce(0, +) - usable
        if overflow > 0 {
            // Take the excess out of the segments that can spare it.
            let shrinkable = widths.enumerated().filter { $0.element > Self.minimumWidth }
            let slack = shrinkable.reduce(0) { $0 + ($1.element - Self.minimumWidth) }
            if slack > 0 {
                for (index, width) in shrinkable {
                    widths[index] = width - overflow * (width - Self.minimumWidth) / slack
                }
            }
        }
        return widths
    }
}

/// Names every segment, in the bar's order. Text stays in ink colors; the
/// swatch beside it carries the identity.
struct CapacityLegend: View {
    let segments: [CapacitySegment]

    private let columns = [GridItem(.adaptive(minimum: 168), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(segments) { segment in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(segment.color.opacity(segment.isTrack ? 0.55 : 1))
                        .frame(width: 10, height: 10)
                    Text(segment.label)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(ByteFormat.string(segment.size))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
