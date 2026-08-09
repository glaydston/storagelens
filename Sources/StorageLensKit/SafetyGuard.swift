import Foundation

public enum SafetyError: Error, LocalizedError, Equatable {
    case outsideAllowedRoots(URL)
    case isAllowedRoot(URL)
    case protectedPath(URL)
    case tooShallow(URL)

    public var errorDescription: String? {
        switch self {
        case .outsideAllowedRoots(let url):
            L("%@ is not inside a folder StorageLens is allowed to clean.", url.path)
        case .isAllowedRoot(let url):
            L("%@ is a cleanup folder itself; only its contents can be removed.", url.path)
        case .protectedPath(let url):
            L("%@ is a protected system location.", url.path)
        case .tooShallow(let url):
            L("%@ is too close to the root of the disk to be removed.", url.path)
        }
    }
}

/// The last line of defence before anything is deleted.
///
/// Every removal goes through `validate` regardless of how the item was
/// discovered, so a bug in scanning or in the UI still can't reach outside the
/// allow-list.
public struct SafetyGuard: Sendable {
    /// Prefixes that are never touched, even if a rule somehow points into them.
    public static let protectedPrefixes = [
        "/System",
        "/bin",
        "/sbin",
        "/usr",
        "/etc",
        "/var/db",
        "/private/var/db",
        "/Library/Apple",
        "/Applications",
        "/Volumes",
    ]

    /// Minimum number of path components. `/Users/me/Downloads/x` has 5, which
    /// is the shallowest thing any rule can legitimately produce.
    public static let minimumComponents = 5

    public init() {}

    /// Throws unless `url` is a strict descendant of one of `allowedRoots`.
    ///
    /// Symlinks are resolved on the *parent* directory only: a symlink is
    /// deleted as a link, never followed to its target, but a link planted
    /// midway through the path can't be used to escape the allow-list either.
    public static func validate(_ url: URL, allowedRoots: [URL]) throws {
        let resolved = resolvedForDeletion(url)
        let components = resolved.pathComponents

        guard components.count >= minimumComponents else {
            throw SafetyError.tooShallow(resolved)
        }

        for prefix in protectedPrefixes where isDescendant(resolved.path, of: prefix) {
            throw SafetyError.protectedPath(resolved)
        }

        let roots = allowedRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        if roots.contains(where: { $0.path == resolved.path }) {
            throw SafetyError.isAllowedRoot(resolved)
        }
        guard roots.contains(where: { isDescendant(resolved.path, of: $0.path) }) else {
            throw SafetyError.outsideAllowedRoots(resolved)
        }
    }

    public static func isValid(_ url: URL, allowedRoots: [URL]) -> Bool {
        (try? validate(url, allowedRoots: allowedRoots)) != nil
    }

    /// Canonical path of the item, with the *containing* directory resolved but
    /// the final component left alone so symlinks are removed, not followed.
    static func resolvedForDeletion(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return parent.appendingPathComponent(standardized.lastPathComponent).standardizedFileURL
    }

    /// True when `path` sits strictly below `ancestor`, comparing whole
    /// components so `/Users/mel` is not treated as a parent of `/Users/melissa`.
    static func isDescendant(_ path: String, of ancestor: String) -> Bool {
        guard path != ancestor else { return false }
        let normalized = ancestor.hasSuffix("/") ? ancestor : ancestor + "/"
        return path.hasPrefix(normalized)
    }
}
