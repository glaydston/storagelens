import Foundation
import Testing
@testable import StorageLensKit

@Suite("DiskScanner")
struct DiskScannerTests {
    @Test("lists children largest first with recursive sizes")
    func listsChildrenBySize() async throws {
        let tree = try TempTree()
        let root = try tree.directory("cache")
        try tree.file("cache/small.bin", bytes: 1_000)
        try tree.file("cache/big/one.bin", bytes: 40_000)
        try tree.file("cache/big/two.bin", bytes: 40_000)

        let scan = await DiskScanner().scan(rule(root: root))

        #expect(scan.items.map(\.name) == ["big", "small.bin"])
        #expect(scan.items[0].isDirectory)
        #expect(scan.items[0].size >= 80_000)
        #expect(scan.totalSize == scan.items.reduce(0) { $0 + $1.size })
    }

    @Test("skips excluded names")
    func skipsExcluded() async throws {
        let tree = try TempTree()
        let root = try tree.directory("cache")
        try tree.file("cache/keep.bin", bytes: 512)
        try tree.file("cache/Homebrew/skip.bin", bytes: 4_096)

        let scan = await DiskScanner().scan(rule(root: root, excluded: ["Homebrew"]))

        #expect(scan.items.map(\.name) == ["keep.bin"])
    }

    @Test("a missing root scans as empty rather than failing")
    func missingRoot() async throws {
        let tree = try TempTree()
        let scan = await DiskScanner().scan(rule(root: tree.root.appendingPathComponent("nope")))

        #expect(scan.isEmpty)
        #expect(!scan.accessDenied)
    }

    @Test("symlinks are not followed when measuring size")
    func doesNotFollowSymlinks() async throws {
        let tree = try TempTree()
        let root = try tree.directory("cache")
        let heavy = try tree.directory("heavy")
        try tree.file("heavy/payload.bin", bytes: 200_000)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link"),
            withDestinationURL: heavy
        )

        let scan = await DiskScanner().scan(rule(root: root))

        #expect(scan.totalSize < 200_000)
    }

    @Test("scanning many rules delivers one result per rule")
    func scansAllRules() async throws {
        let tree = try TempTree()
        let rules = try (0..<5).map { index -> CleanupRule in
            let root = try tree.directory("cache\(index)")
            try tree.file("cache\(index)/file.bin", bytes: 1_024 * (index + 1))
            return rule(id: "rule-\(index)", root: root)
        }

        var received: [String] = []
        for await scan in DiskScanner().scan(rules) {
            received.append(scan.rule.id)
        }

        #expect(Set(received) == Set(rules.map(\.id)))
    }

    private func rule(
        id: String = "test",
        root: URL,
        excluded: Set<String> = []
    ) -> CleanupRule {
        CleanupRule(
            id: id,
            title: "Test",
            detail: "Test rule",
            group: .system,
            root: root,
            excludedNames: excluded
        )
    }
}

/// Records what would have been removed instead of touching the file system.
final class RecordingFileOperations: FileOperations, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var trashed: [URL] = []
    private(set) var deleted: [URL] = []
    var failingNames: Set<String> = []

    func trash(_ url: URL) throws {
        try record(url, into: \.trashed)
    }

    func delete(_ url: URL) throws {
        try record(url, into: \.deleted)
    }

    private func record(_ url: URL, into keyPath: ReferenceWritableKeyPath<RecordingFileOperations, [URL]>) throws {
        if failingNames.contains(url.lastPathComponent) {
            throw CocoaError(.fileWriteNoPermission)
        }
        lock.lock()
        defer { lock.unlock() }
        self[keyPath: keyPath].append(url)
    }
}

@Suite("Cleaner")
struct CleanerTests {
    @Test("trashes valid items and reports what was reclaimed")
    func trashesValidItems() throws {
        let tree = try TempTree()
        let root = try tree.directory("cache")
        let items = [
            try item(tree.file("cache/a.bin", bytes: 1_024), size: 1_024),
            try item(tree.file("cache/b.bin", bytes: 2_048), size: 2_048),
        ]

        let operations = RecordingFileOperations()
        let report = Cleaner(operations: operations)
            .remove(items, removal: .trash, allowedRoots: [root])

        #expect(operations.trashed.count == 2)
        #expect(operations.deleted.isEmpty)
        #expect(report.failed.isEmpty)
        #expect(report.reclaimed == 3_072)
    }

    @Test("refuses an item outside the allowed roots even if it was handed one")
    func refusesEscapee() throws {
        let tree = try TempTree()
        let root = try tree.directory("cache")
        let outsider = try item(tree.file("elsewhere/precious.txt", bytes: 10), size: 10)

        let operations = RecordingFileOperations()
        let report = Cleaner(operations: operations)
            .remove([outsider], removal: .trash, allowedRoots: [root])

        #expect(operations.trashed.isEmpty)
        #expect(report.reclaimed == 0)
        #expect(report.failed.count == 1)
    }

    @Test("permanent removal is used only when the rule asks for it")
    func permanentRemoval() throws {
        let tree = try TempTree()
        let root = try tree.directory("trash")
        let items = [try item(tree.file("trash/old.bin", bytes: 64), size: 64)]

        let operations = RecordingFileOperations()
        _ = Cleaner(operations: operations)
            .remove(items, removal: .permanent, allowedRoots: [root])

        #expect(operations.deleted.count == 1)
        #expect(operations.trashed.isEmpty)
    }

    @Test("one failure doesn't stop the rest")
    func continuesAfterFailure() throws {
        let tree = try TempTree()
        let root = try tree.directory("cache")
        let items = [
            try item(tree.file("cache/locked.bin", bytes: 100), size: 100),
            try item(tree.file("cache/fine.bin", bytes: 200), size: 200),
        ]

        let operations = RecordingFileOperations()
        operations.failingNames = ["locked.bin"]
        let report = Cleaner(operations: operations)
            .remove(items, removal: .trash, allowedRoots: [root])

        #expect(report.succeeded.count == 1)
        #expect(report.failed.count == 1)
        #expect(report.reclaimed == 200)
        #expect(report.failed.first?.error != nil)
    }

    private func item(_ url: URL, size: Int64) -> ScannedItem {
        ScannedItem(
            url: url,
            name: url.lastPathComponent,
            size: size,
            modified: nil,
            isDirectory: false
        )
    }
}

@Suite("CleanupCatalog")
struct CleanupCatalogTests {
    @Test("rule identifiers are unique")
    func uniqueIdentifiers() throws {
        let tree = try TempTree()
        let rules = CleanupCatalog.rules(home: tree.root, environment: [:])

        #expect(Set(rules.map(\.id)).count == rules.count)
    }

    @Test("every rule lives inside the home directory")
    func rootsStayInHome() throws {
        let tree = try TempTree()
        let home = tree.root.resolvingSymlinksInPath()
        let rules = CleanupCatalog.rules(home: tree.root, environment: [:])

        for rule in rules {
            #expect(rule.root.resolvingSymlinksInPath().path.hasPrefix(home.path))
        }
    }

    @Test("the Trash rule deletes permanently, everything else trashes")
    func removalModes() throws {
        let tree = try TempTree()
        let rules = CleanupCatalog.rules(home: tree.root, environment: [:])

        #expect(rules.filter { $0.removal == .permanent }.map(\.id) == ["trash"])
    }

    @Test("HOMEBREW_CACHE overrides the default Homebrew path")
    func honoursHomebrewCacheEnvironment() throws {
        let tree = try TempTree()
        let custom = try tree.directory("brew-cache")
        let rules = CleanupCatalog.rules(
            home: tree.root,
            environment: ["HOMEBREW_CACHE": custom.path]
        )

        let brew = try #require(rules.first { $0.id == "homebrew-cache" })
        #expect(brew.root.path == custom.path)
    }

    @Test("sizes render the way Finder shows them")
    func byteFormatting() {
        #expect(ByteFormat.string(0) == "0 KB")
        #expect(ByteFormat.string(-5) == "0 KB")
        #expect(ByteFormat.string(1_500_000).contains("MB"))
    }
}
