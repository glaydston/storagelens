import Foundation

/// One removable entry found inside a rule's root.
public struct ScannedItem: Sendable, Hashable, Identifiable {
    public var id: String { url.path }

    public let url: URL
    public let name: String
    /// Bytes actually allocated on disk, summed recursively for directories.
    public let size: Int64
    public let modified: Date?
    public let isDirectory: Bool

    public init(url: URL, name: String, size: Int64, modified: Date?, isDirectory: Bool) {
        self.url = url
        self.name = name
        self.size = size
        self.modified = modified
        self.isDirectory = isDirectory
    }
}

/// Result of scanning a single rule.
public struct CategoryScan: Sendable, Identifiable {
    public var id: String { rule.id }

    public let rule: CleanupRule
    public let items: [ScannedItem]
    /// Set when the root exists but couldn't be read — almost always a missing
    /// Full Disk Access grant.
    public let accessDenied: Bool

    public init(rule: CleanupRule, items: [ScannedItem], accessDenied: Bool = false) {
        self.rule = rule
        self.items = items
        self.accessDenied = accessDenied
    }

    public var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    public var isEmpty: Bool { items.isEmpty }
}

/// Measures what a rule's root currently holds. Read-only: this type never
/// mutates the file system.
///
/// `@unchecked Sendable` because `FileManager` isn't `Sendable`; only its
/// thread-safe read APIs are used here, and each concurrent scan gets its own
/// enumerator.
public struct DiskScanner: @unchecked Sendable {
    let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Lists the immediate children of `rule.root`, largest first.
    ///
    /// A missing root is not an error — most machines only have a subset of
    /// these tools installed — it just yields an empty scan.
    public func scan(_ rule: CleanupRule) async -> CategoryScan {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rule.root.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return CategoryScan(rule: rule, items: [])
        }

        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: rule.root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: []
            )
        } catch {
            return CategoryScan(rule: rule, items: [], accessDenied: true)
        }

        var items: [ScannedItem] = []
        for child in children {
            if Task.isCancelled { break }
            guard !rule.excludedNames.contains(child.lastPathComponent) else { continue }

            let values = try? child.resourceValues(
                forKeys: [.isDirectoryKey, .contentModificationDateKey]
            )
            let isDir = values?.isDirectory ?? false
            items.append(ScannedItem(
                url: child,
                name: child.lastPathComponent,
                size: Self.size(of: child, fileManager: fileManager),
                modified: values?.contentModificationDate,
                isDirectory: isDir
            ))
        }

        items.sort { $0.size > $1.size }
        return CategoryScan(rule: rule, items: items)
    }

    /// Scans every rule concurrently, delivering each result as it lands so the
    /// UI can fill in progressively.
    public func scan(_ rules: [CleanupRule]) -> AsyncStream<CategoryScan> {
        AsyncStream { continuation in
            // Detached so a caller on the main actor doesn't end up walking the
            // file system on the main thread.
            let task = Task.detached {
                await withTaskGroup(of: CategoryScan.self) { group in
                    for rule in rules {
                        group.addTask { await self.scan(rule) }
                    }
                    for await result in group {
                        continuation.yield(result)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Allocated size on disk, recursing into directories without following
    /// symlinks (`FileManager`'s enumerator does not descend into linked dirs).
    public static func size(of url: URL, fileManager: FileManager = .default) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
        ]

        func allocatedSize(_ url: URL) -> Int64 {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isSymbolicLink != true
            else { return 0 }
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        guard isDirectory.boolValue else { return allocatedSize(url) }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            // No `skipsPackageDescendants`: bundles are exactly where the bytes
            // hide, and undercounting would misreport how much a clean frees.
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        var counter = 0
        for case let child as URL in enumerator {
            counter += 1
            // Cancellation is checked in batches; `resourceValues` is the hot path.
            if counter % 512 == 0, Task.isCancelled { break }
            total += allocatedSize(child)
        }
        return total
    }
}
