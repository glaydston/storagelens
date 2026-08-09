import Foundation

/// A place on disk whose *children* are candidates for removal.
///
/// A rule never targets the root itself — only what is inside it — so cleaning
/// can't destroy the directory structure the OS or a tool expects to exist.
public struct CleanupRule: Sendable, Identifiable, Hashable {
    /// How items in this rule are disposed of.
    public enum Removal: String, Sendable, Hashable {
        /// Moved to the Trash, recoverable by the user. The default everywhere.
        case trash
        /// Deleted outright. Only used for the Trash itself, where trashing is
        /// impossible, and always behind an extra confirmation in the UI.
        case permanent
    }

    /// Whether the item is regenerable junk or something the user should look at.
    public enum Risk: String, Sendable, Hashable {
        /// Caches and logs an app will simply rebuild. Pre-selected after a scan.
        case safe
        /// Real data, or artifacts that are expensive/impossible to recreate.
        /// Never pre-selected — the user has to tick each one.
        case review
    }

    public enum Group: String, Sendable, Hashable, CaseIterable {
        case system = "System"
        case developer = "Developer"
        case packageManagers = "Package Managers"
        case applications = "Applications"
        case large = "Needs Review"
    }

    public let id: String
    public let title: String
    public let detail: String
    public let group: Group
    public let root: URL
    public let removal: Removal
    public let risk: Risk
    /// Child names that are never offered for removal.
    public let excludedNames: Set<String>

    public init(
        id: String,
        title: String,
        detail: String,
        group: Group,
        root: URL,
        removal: Removal = .trash,
        risk: Risk = .safe,
        excludedNames: Set<String> = []
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.group = group
        self.root = root
        self.removal = removal
        self.risk = risk
        self.excludedNames = excludedNames
    }
}

/// The set of rules StorageLens knows about.
public enum CleanupCatalog {
    /// Builds the rule set for a home directory. `home` is injectable so tests
    /// can run against a scratch directory instead of the real one.
    public static func rules(
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [CleanupRule] {
        var rules: [CleanupRule] = []

        func path(_ components: String...) -> URL {
            components.reduce(home) { $0.appendingPathComponent($1) }
        }

        // MARK: System

        rules.append(CleanupRule(
            id: "trash",
            title: "Trash",
            detail: "Everything in ~/.Trash. Emptying it here is permanent.",
            group: .system,
            root: path(".Trash"),
            removal: .permanent,
            risk: .review
        ))

        rules.append(CleanupRule(
            id: "user-caches",
            title: "Application Caches",
            detail: "~/Library/Caches — rebuilt by apps on next launch.",
            group: .system,
            root: path("Library", "Caches"),
            // Owned by dedicated rules below, so they aren't offered twice.
            excludedNames: ["Homebrew", "pip", "Yarn", "CocoaPods", "go-build", "uv", "deno"]
        ))

        rules.append(CleanupRule(
            id: "user-logs",
            title: "Application Logs",
            detail: "~/Library/Logs — diagnostic output from apps you've run.",
            group: .system,
            root: path("Library", "Logs")
        ))

        rules.append(CleanupRule(
            id: "crash-reports",
            title: "Crash Reports",
            detail: "~/Library/Logs/DiagnosticReports — crash and spin logs.",
            group: .system,
            root: path("Library", "Logs", "DiagnosticReports")
        ))

        // MARK: Developer

        let xcode = path("Library", "Developer", "Xcode")
        rules.append(CleanupRule(
            id: "xcode-derived-data",
            title: "Xcode Derived Data",
            detail: "Build products and indexes. Xcode rebuilds them on demand.",
            group: .developer,
            root: xcode.appendingPathComponent("DerivedData")
        ))

        rules.append(CleanupRule(
            id: "xcode-archives",
            title: "Xcode Archives",
            detail: "Shipped builds and their dSYMs — needed to symbolicate crashes.",
            group: .developer,
            root: xcode.appendingPathComponent("Archives"),
            risk: .review
        ))

        rules.append(CleanupRule(
            id: "xcode-device-support",
            title: "iOS Device Support",
            detail: "Symbols cached per connected device and OS version.",
            group: .developer,
            root: xcode.appendingPathComponent("iOS DeviceSupport")
        ))

        rules.append(CleanupRule(
            id: "simulator-caches",
            title: "Simulator Caches",
            detail: "~/Library/Developer/CoreSimulator/Caches.",
            group: .developer,
            root: path("Library", "Developer", "CoreSimulator", "Caches")
        ))

        rules.append(CleanupRule(
            id: "swiftpm-cache",
            title: "Swift Package Manager Cache",
            detail: "Cloned and cached package checkouts.",
            group: .developer,
            root: path("Library", "Caches", "org.swift.swiftpm")
        ))

        // MARK: Package managers

        let brewCache = environment["HOMEBREW_CACHE"].map(URL.init(fileURLWithPath:))
            ?? path("Library", "Caches", "Homebrew")
        rules.append(CleanupRule(
            id: "homebrew-cache",
            title: "Homebrew Cache",
            detail: "Downloaded bottles and source tarballs.",
            group: .packageManagers,
            root: brewCache
        ))

        let managers: [(String, String, String, [String])] = [
            ("npm", "npm Cache", "~/.npm/_cacache", [".npm", "_cacache"]),
            ("yarn", "Yarn Cache", "~/Library/Caches/Yarn", ["Library", "Caches", "Yarn"]),
            ("pnpm", "pnpm Store", "~/Library/pnpm/store", ["Library", "pnpm", "store"]),
            ("pip", "pip Cache", "~/Library/Caches/pip", ["Library", "Caches", "pip"]),
            ("uv", "uv Cache", "~/Library/Caches/uv", ["Library", "Caches", "uv"]),
            ("go-build", "Go Build Cache", "~/Library/Caches/go-build", ["Library", "Caches", "go-build"]),
            ("cargo", "Cargo Registry Cache", "~/.cargo/registry/cache", [".cargo", "registry", "cache"]),
            ("gradle", "Gradle Caches", "~/.gradle/caches", [".gradle", "caches"]),
            ("cocoapods", "CocoaPods Cache", "~/Library/Caches/CocoaPods", ["Library", "Caches", "CocoaPods"]),
            ("deno", "Deno Cache", "~/Library/Caches/deno", ["Library", "Caches", "deno"]),
        ]
        for (id, title, detail, components) in managers {
            rules.append(CleanupRule(
                id: id,
                title: title,
                detail: detail,
                group: .packageManagers,
                root: components.reduce(home) { $0.appendingPathComponent($1) }
            ))
        }

        // MARK: Applications — one rule per sandboxed container's cache dir.

        let containers = path("Library", "Containers")
        let containerDirs = (try? fileManager.contentsOfDirectory(
            at: containers,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for container in containerDirs.sorted(by: { $0.path < $1.path }) {
            let cache = container.appendingPathComponent("Data/Library/Caches")
            guard fileManager.fileExists(atPath: cache.path) else { continue }
            rules.append(CleanupRule(
                id: "container-\(container.lastPathComponent)",
                title: container.lastPathComponent,
                detail: "Sandboxed cache for \(container.lastPathComponent).",
                group: .applications,
                root: cache
            ))
        }

        // MARK: Needs review

        rules.append(CleanupRule(
            id: "ios-backups",
            title: "iOS Device Backups",
            detail: "Full device backups made by Finder. Often tens of gigabytes.",
            group: .large,
            root: path("Library", "Application Support", "MobileSync", "Backup"),
            risk: .review
        ))

        rules.append(CleanupRule(
            id: "downloads",
            title: "Downloads",
            detail: "Your ~/Downloads folder, largest first. Nothing here is junk by default.",
            group: .large,
            root: path("Downloads"),
            risk: .review
        ))

        rules.append(CleanupRule(
            id: "mail-downloads",
            title: "Mail Attachments",
            detail: "Attachments Mail saved to disk. Requires Full Disk Access.",
            group: .large,
            root: path("Library", "Containers", "com.apple.mail", "Data", "Library", "Mail Downloads"),
            risk: .review
        ))

        return rules
    }

    /// Roots that `SafetyGuard` will permit deletions under, derived from the rules.
    public static func allowedRoots(for rules: [CleanupRule]) -> [URL] {
        rules.map(\.root)
    }
}
