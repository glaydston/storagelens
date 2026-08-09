import Foundation
import Observation
import StorageLensKit

/// Everything the UI observes: the current scan, what the user ticked, and the
/// result of the last clean.
@MainActor
@Observable
final class ScanModel {
    enum Route: Hashable {
        case overview
        case category(String)
    }

    private(set) var volume: VolumeInfo?
    private(set) var scans: [CategoryScan] = []
    private(set) var isScanning = false
    private(set) var scannedCount = 0
    private(set) var ruleCount = 0
    private(set) var lastReport: CleanupReport?

    var route: Route? = .overview
    /// Item paths the user has ticked, across all categories.
    var selection: Set<String> = []

    private var rules: [CleanupRule] = []
    private var scanTask: Task<Void, Never>?
    private let scanner = DiskScanner()
    private let cleaner = Cleaner()

    var progress: Double {
        ruleCount == 0 ? 0 : Double(scannedCount) / Double(ruleCount)
    }

    var reclaimableTotal: Int64 {
        scans.filter { $0.rule.risk == .safe }.reduce(0) { $0 + $1.totalSize }
    }

    var scannedTotal: Int64 {
        scans.reduce(0) { $0 + $1.totalSize }
    }

    var needsFullDiskAccess: Bool {
        scans.contains(where: \.accessDenied)
    }

    var nonEmptyScans: [CategoryScan] {
        scans.filter { !$0.isEmpty }.sorted { $0.totalSize > $1.totalSize }
    }

    func scans(in group: CleanupRule.Group) -> [CategoryScan] {
        nonEmptyScans.filter { $0.rule.group == group }
    }

    func scan(id: String) -> CategoryScan? {
        scans.first { $0.rule.id == id }
    }

    var selectedItems: [(rule: CleanupRule, items: [ScannedItem])] {
        scans.compactMap { scan in
            let picked = scan.items.filter { selection.contains($0.id) }
            return picked.isEmpty ? nil : (scan.rule, picked)
        }
    }

    var selectedSize: Int64 {
        selectedItems.reduce(0) { $0 + $1.items.reduce(0) { $0 + $1.size } }
    }

    var selectionIncludesPermanent: Bool {
        selectedItems.contains { $0.rule.removal == .permanent }
    }

    // MARK: - Scanning

    func rescan() {
        scanTask?.cancel()
        volume = try? VolumeInfo.current()
        rules = CleanupCatalog.rules()
        scans = []
        selection = []
        lastReport = nil
        scannedCount = 0
        ruleCount = rules.count
        isScanning = true

        let rules = rules
        scanTask = Task { [scanner] in
            for await result in scanner.scan(rules) {
                guard !Task.isCancelled else { break }
                self.ingest(result)
            }
            self.isScanning = false
        }
    }

    private func ingest(_ result: CategoryScan) {
        scans.append(result)
        scannedCount += 1
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
    }

    // MARK: - Selection

    func isSelected(_ item: ScannedItem) -> Bool {
        selection.contains(item.id)
    }

    func toggle(_ item: ScannedItem, on: Bool) {
        if on { selection.insert(item.id) } else { selection.remove(item.id) }
    }

    func selectAll(in scan: CategoryScan) {
        selection.formUnion(scan.items.map(\.id))
    }

    func deselectAll(in scan: CategoryScan) {
        selection.subtract(scan.items.map(\.id))
    }

    /// Ticks everything in every `.safe` category. `.review` categories are
    /// deliberately left alone — that's what makes them "review".
    func selectAllSafe() {
        for scan in scans where scan.rule.risk == .safe {
            selection.formUnion(scan.items.map(\.id))
        }
    }

    // MARK: - Cleaning

    func cleanSelected() {
        let groups = selectedItems
        guard !groups.isEmpty else { return }

        let allowedRoots = CleanupCatalog.allowedRoots(for: rules)
        var outcomes: [CleanupOutcome] = []
        for (rule, items) in groups {
            let report = cleaner.remove(items, removal: rule.removal, allowedRoots: allowedRoots)
            outcomes.append(contentsOf: report.outcomes)
        }

        let report = CleanupReport(outcomes: outcomes)
        lastReport = report

        // Drop what actually went away; anything that failed stays visible.
        let removed = Set(report.succeeded.map { $0.item.id })
        scans = scans.map { scan in
            CategoryScan(
                rule: scan.rule,
                items: scan.items.filter { !removed.contains($0.id) },
                accessDenied: scan.accessDenied
            )
        }
        selection.subtract(removed)
        volume = try? VolumeInfo.current()
    }
}
