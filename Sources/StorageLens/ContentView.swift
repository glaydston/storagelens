import AppKit
import SwiftUI
import StorageLensKit

struct ContentView: View {
    @Environment(ScanModel.self) private var model
    @State private var confirmingClean = false

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            Group {
                switch model.route {
                case .category(let id):
                    if let scan = model.scan(id: id) {
                        CategoryDetailView(scan: scan)
                    } else {
                        ContentUnavailableView("Category not scanned", systemImage: "questionmark.folder")
                    }
                case .overview, .none:
                    OverviewView()
                }
            }
            .toolbar { toolbar }
        }
        .confirmationDialog(confirmTitle, isPresented: $confirmingClean) {
            Button(confirmAction, role: .destructive) { model.cleanSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if model.isScanning {
                Button("Stop", systemImage: "stop.circle") { model.cancelScan() }
            } else {
                Button("Rescan", systemImage: "arrow.clockwise") { model.rescan() }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                confirmingClean = true
            } label: {
                Label(
                    model.selection.isEmpty
                        ? "Clean"
                        : "Clean \(ByteFormat.string(model.selectedSize))",
                    systemImage: "trash"
                )
            }
            .disabled(model.selection.isEmpty)
        }
    }

    private var confirmTitle: String {
        model.selectionIncludesPermanent
            ? "Delete \(model.selection.count) items?"
            : "Move \(model.selection.count) items to the Trash?"
    }

    private var confirmAction: String {
        model.selectionIncludesPermanent ? "Delete" : "Move to Trash"
    }

    private var confirmMessage: String {
        let size = ByteFormat.string(model.selectedSize)
        return model.selectionIncludesPermanent
            ? "\(size) will be freed. Your selection includes items already in the Trash, which cannot be recovered once deleted."
            : "\(size) will be freed. Everything goes to the Trash, so you can put it back until you empty it."
    }
}

struct SidebarView: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.route) {
            Label("Overview", systemImage: "chart.pie")
                .tag(ScanModel.Route.overview)

            ForEach(CleanupRule.Group.allCases, id: \.self) { group in
                let scans = model.scans(in: group)
                if !scans.isEmpty {
                    Section(group.rawValue) {
                        ForEach(scans) { scan in
                            SidebarRow(scan: scan, selectedCount: selectedCount(in: scan))
                                .tag(ScanModel.Route.category(scan.rule.id))
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if model.isScanning {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: model.progress)
                    Text("Scanning \(model.scannedCount) of \(model.ruleCount)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.bar)
            }
        }
    }

    private func selectedCount(in scan: CategoryScan) -> Int {
        scan.items.filter { model.selection.contains($0.id) }.count
    }
}

struct SidebarRow: View {
    let scan: CategoryScan
    let selectedCount: Int

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(CategoryPalette.color(for: scan.rule.group))
            VStack(alignment: .leading, spacing: 1) {
                Text(scan.rule.title)
                    .lineLimit(1)
                if selectedCount > 0 {
                    Text("\(selectedCount) selected")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
            }
            Spacer()
            Text(ByteFormat.string(scan.totalSize))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var icon: String {
        switch scan.rule.group {
        case .system: scan.rule.id == "trash" ? "trash" : "gearshape"
        case .developer: "hammer"
        case .packageManagers: "shippingbox"
        case .applications: "app.badge"
        case .large: "exclamationmark.triangle"
        }
    }
}
