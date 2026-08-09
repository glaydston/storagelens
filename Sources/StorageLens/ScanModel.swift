import AppKit
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

    func total(in group: CleanupRule.Group) -> Int64 {
        scans.filter { $0.rule.group == group }.reduce(0) { $0 + $1.totalSize }
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

    /// A populated model with plausible numbers, for SwiftUI previews and for
    /// `--snapshot` (which renders the Overview without scanning a real disk).
    static func preview() -> ScanModel {
        let model = ScanModel()
        model.volume = VolumeInfo(
            name: "Macintosh HD",
            url: URL(fileURLWithPath: "/"),
            totalCapacity: 994_662_584_320,
            availableCapacity: 268_435_456_000
        )

        let fixtures: [(String, String, CleanupRule.Group, CleanupRule.Risk, [Int64])] = [
            ("xcode-derived-data", "Xcode Derived Data", .developer, .safe, [24_800_000_000, 9_100_000_000, 3_400_000_000]),
            ("user-caches", "Application Caches", .system, .safe, [6_200_000_000, 2_800_000_000, 900_000_000]),
            ("ios-backups", "iOS Device Backups", .large, .review, [18_400_000_000]),
            ("homebrew-cache", "Homebrew Cache", .packageManagers, .safe, [4_700_000_000, 1_200_000_000]),
            ("container-com.apple.Safari", "com.apple.Safari", .applications, .safe, [1_900_000_000]),
            ("trash", "Trash", .system, .review, [3_100_000_000, 640_000_000]),
            ("npm", "npm Cache", .packageManagers, .safe, [2_300_000_000]),
            ("user-logs", "Application Logs", .system, .safe, [410_000_000]),
        ]

        model.scans = fixtures.map { id, title, group, risk, sizes in
            let root = URL(fileURLWithPath: "/Users/preview/Library/\(id)")
            let rule = CleanupRule(
                id: id,
                title: title,
                detail: "Preview fixture",
                group: group,
                root: root,
                removal: id == "trash" ? .permanent : .trash,
                risk: risk
            )
            let items = sizes.enumerated().map { index, size in
                ScannedItem(
                    url: root.appendingPathComponent("item-\(index)"),
                    name: "item-\(index)",
                    size: size,
                    modified: nil,
                    isDirectory: true
                )
            }
            return CategoryScan(rule: rule, items: items)
        }
        model.ruleCount = model.scans.count
        model.scannedCount = model.scans.count

        if let trash = model.scans.first(where: { $0.rule.id == trashRuleID }),
           let item = trash.items.first {
            model.lastReport = CleanupReport(outcomes: [
                CleanupOutcome(item: item, removal: .trash, error: nil),
                CleanupOutcome(
                    item: ScannedItem(
                        url: trash.rule.root.appendingPathComponent("old"),
                        name: "old", size: 2_100_000_000, modified: nil, isDirectory: true
                    ),
                    removal: .trash, error: nil
                ),
            ])
        }
        return model
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

        // Whatever was trashed just landed in the Trash, so that category is now
        // stale — and it's the one the user is about to look at.
        refreshTrash()
    }

    /// The Trash rule's id, so the UI can route to it after a clean.
    static let trashRuleID = "trash"

    var trashURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
    }

    /// Opens the Trash in Finder — where the space actually gets reclaimed.
    func revealTrash() {
        NSWorkspace.shared.open(trashURL)
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func refreshTrash() {
        guard let rule = rules.first(where: { $0.id == Self.trashRuleID }) else { return }
        Task { [scanner] in
            let result = await scanner.scan(rule)
            self.replace(result)
        }
    }

    private func replace(_ scan: CategoryScan) {
        if let index = scans.firstIndex(where: { $0.rule.id == scan.rule.id }) {
            scans[index] = scan
        } else {
            scans.append(scan)
        }
    }
}
