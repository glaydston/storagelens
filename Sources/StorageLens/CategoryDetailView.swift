import AppKit
import SwiftUI
import StorageLensKit

struct CategoryDetailView: View {
    @Environment(ScanModel.self) private var model
    let scan: CategoryScan

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if scan.accessDenied {
                ContentUnavailableView(
                    L("Couldn't read this folder"),
                    systemImage: "lock",
                    description: Text(L("Grant Full Disk Access in System Settings, then rescan."))
                )
            } else if scan.items.isEmpty {
                ContentUnavailableView(
                    L("Nothing here"),
                    systemImage: "sparkles",
                    description: Text(L("%@ is empty or doesn't exist.", scan.rule.root.path))
                )
            } else {
                itemList
            }
        }
        .navigationTitle(L(scan.rule.title))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L(scan.rule.detail))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text(scan.rule.root.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if scan.rule.removal == .permanent {
                    Label(L("Deleted permanently"), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(LPlural("%lld items", scan.items.count))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(ByteFormat.string(scan.totalSize))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(L("Select All")) { model.selectAll(in: scan) }
                Button(L("Select None")) { model.deselectAll(in: scan) }
                Spacer()
                Button(L("Open in Finder")) { model.reveal(scan.rule.root) }
                    .disabled(!FileManager.default.fileExists(atPath: scan.rule.root.path))
            }
            .controlSize(.small)
        }
        .padding(16)
    }

    private var itemList: some View {
        List {
            ForEach(scan.items) { item in
                ItemRow(item: item)
            }
        }
        .listStyle(.inset)
    }
}

struct ItemRow: View {
    @Environment(ScanModel.self) private var model
    let item: ScannedItem

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { model.isSelected(item) },
                set: { model.toggle(item, on: $0) }
            ))
            .labelsHidden()

            Image(systemName: item.isDirectory ? "folder" : "doc")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1)
                if let modified = item.modified {
                    Text(L("Modified %@", modified.formatted(.relative(presentation: .named))))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text(ByteFormat.string(item.size))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help(L("Reveal in Finder"))
        }
        .padding(.vertical, 2)
    }
}
