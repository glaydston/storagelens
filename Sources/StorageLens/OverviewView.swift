import AppKit
import SwiftUI
import StorageLensKit

struct OverviewView: View {
    var body: some View {
        ScrollView {
            OverviewContent()
        }
        .navigationTitle(L("Overview"))
    }
}

/// The Overview's content, outside the scroll view so `ImageRenderer` can lay
/// it out for `--snapshot` (a ScrollView renders empty).
struct OverviewContent: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                if let volume = model.volume {
                    VolumeCard(volume: volume, segments: capacitySegments(for: volume))
                }

                if model.needsFullDiskAccess {
                    FullDiskAccessBanner()
                }

                if let report = model.lastReport {
                    CleanReportCard(report: report)
                }

                summary

                if !model.nonEmptyScans.isEmpty {
                    Text(L("Biggest categories"))
                        .font(.headline)
                    ForEach(model.nonEmptyScans.prefix(12)) { scan in
                        CategoryBar(scan: scan, maximum: model.nonEmptyScans.first?.totalSize ?? 1)
                            .onTapGesture { model.route = .category(scan.rule.id) }
                    }
                }

                Divider().padding(.top, 8)
                HStack(spacing: 6) {
                    Text(AppInfo.summary)
                    Text("·")
                    Text(L("Source"))
                        .underline()
                        .onTapGesture { NSWorkspace.shared.open(AppInfo.repository) }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One segment per group that found something, then everything else in use,
    /// then free space — so the bar always sums to the volume's capacity.
    private func capacitySegments(for volume: VolumeInfo) -> [CapacitySegment] {
        var segments = CleanupRule.Group.allCases.compactMap { group -> CapacitySegment? in
            let size = model.total(in: group)
            guard size > 0 else { return nil }
            return CapacitySegment(
                id: group.rawValue,
                label: L(group.rawValue),
                size: size,
                color: CategoryPalette.color(for: group)
            )
        }

        let categorized = segments.reduce(Int64(0)) { $0 + $1.size }
        segments.append(CapacitySegment(
            id: "other",
            label: L("Other used"),
            size: max(0, volume.usedCapacity - categorized),
            color: CategoryPalette.otherUsed
        ))
        segments.append(CapacitySegment(
            id: "free",
            label: L("Free"),
            size: volume.availableCapacity,
            color: CategoryPalette.free,
            isTrack: true
        ))
        return segments
    }

    private var summary: some View {
        HStack(spacing: 16) {
            StatTile(
                title: L("Found"),
                value: ByteFormat.string(model.scannedTotal),
                caption: LPlural("across %lld categories", model.nonEmptyScans.count)
            )
            StatTile(
                title: L("Safe to clean"),
                value: ByteFormat.string(model.reclaimableTotal),
                caption: L("caches and logs apps rebuild")
            )
            StatTile(
                title: L("Selected"),
                value: ByteFormat.string(model.selectedSize),
                caption: LPlural("%lld items", model.selection.count)
            )
            Spacer()
            Button(L("Select All Safe")) { model.selectAllSafe() }
                .disabled(model.reclaimableTotal == 0)
        }
    }
}

struct VolumeCard: View {
    let volume: VolumeInfo
    let segments: [CapacitySegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(volume.name).font(.title2.weight(.semibold))
                Spacer()
                Text(L("%@ available", ByteFormat.string(volume.availableCapacity)))
                    .foregroundStyle(.secondary)
            }

            CapacityBar(segments: segments)

            Text(L("%@ used of %@", ByteFormat.string(volume.usedCapacity), ByteFormat.string(volume.totalCapacity)))
                .font(.callout)
                .foregroundStyle(.secondary)

            CapacityLegend(segments: segments)
        }
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            Text(caption).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(minWidth: 140, alignment: .leading)
    }
}

struct CategoryBar: View {
    let scan: CategoryScan
    let maximum: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L(scan.rule.title))
                if scan.rule.risk == .review {
                    Text(L("review"))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.2), in: Capsule())
                }
                Spacer()
                Text(ByteFormat.string(scan.totalSize))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                let fraction = maximum > 0 ? Double(scan.totalSize) / Double(maximum) : 0
                RoundedRectangle(cornerRadius: 3)
                    .fill(CategoryPalette.color(for: scan.rule.group).gradient)
                    .frame(width: max(2, geometry.size.width * fraction), height: 6)
            }
            .frame(height: 6)
        }
        .contentShape(Rectangle())
    }
}

struct CleanReportCard: View {
    let report: CleanupReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                L("Freed %@", ByteFormat.string(report.reclaimed)),
                systemImage: "checkmark.circle"
            )
            .font(.headline)
            .foregroundStyle(.green)

            Text(LPlural("%lld items removed", report.succeeded.count))
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(report.failed.prefix(5)) { outcome in
                Text(L("Couldn't remove %@: %@", outcome.item.name, outcome.error ?? L("unknown error")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if report.failed.count > 5 {
                Text(LPlural("…and %lld more failures", report.failed.count - 5))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct FullDiskAccessBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Some folders couldn't be read")).font(.headline)
                Text(L("Grant StorageLens Full Disk Access to measure protected locations like Mail and app containers."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("Open Settings")) {
                let url = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
                )!
                NSWorkspace.shared.open(url)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
