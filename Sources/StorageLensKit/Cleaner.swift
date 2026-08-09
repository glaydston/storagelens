import Foundation

/// The only two destructive operations in the app, behind a protocol so tests
/// can assert on what *would* happen without losing files.
public protocol FileOperations: Sendable {
    func trash(_ url: URL) throws
    func delete(_ url: URL) throws
}

public struct SystemFileOperations: FileOperations {
    public init() {}

    public func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    public func delete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

public struct CleanupOutcome: Sendable, Identifiable {
    public var id: String { item.url.path }

    public let item: ScannedItem
    public let removal: CleanupRule.Removal
    public let error: String?

    public var succeeded: Bool { error == nil }
    public var reclaimed: Int64 { succeeded ? item.size : 0 }
}

public struct CleanupReport: Sendable {
    public let outcomes: [CleanupOutcome]

    public init(outcomes: [CleanupOutcome]) {
        self.outcomes = outcomes
    }

    public var reclaimed: Int64 { outcomes.reduce(0) { $0 + $1.reclaimed } }
    public var succeeded: [CleanupOutcome] { outcomes.filter(\.succeeded) }
    public var failed: [CleanupOutcome] { outcomes.filter { !$0.succeeded } }
}

/// Removes selected items, one at a time, validating each against the
/// allow-list first. A failure on one item never aborts the rest.
public struct Cleaner: Sendable {
    let operations: FileOperations

    public init(operations: FileOperations = SystemFileOperations()) {
        self.operations = operations
    }

    public func remove(
        _ items: [ScannedItem],
        removal: CleanupRule.Removal,
        allowedRoots: [URL]
    ) -> CleanupReport {
        var outcomes: [CleanupOutcome] = []
        outcomes.reserveCapacity(items.count)

        for item in items {
            let target = SafetyGuard.resolvedForDeletion(item.url)
            do {
                try SafetyGuard.validate(item.url, allowedRoots: allowedRoots)
                switch removal {
                case .trash: try operations.trash(target)
                case .permanent: try operations.delete(target)
                }
                outcomes.append(CleanupOutcome(item: item, removal: removal, error: nil))
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                outcomes.append(CleanupOutcome(item: item, removal: removal, error: message))
            }
        }

        return CleanupReport(outcomes: outcomes)
    }
}
