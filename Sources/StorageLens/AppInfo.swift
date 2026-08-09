import Foundation

/// Single source of truth for the app's identity.
///
/// `Scripts/build-app.sh` reads `version` out of this file when it writes
/// Info.plist, so bumping it here is the only place a release version changes.
enum AppInfo {
    static let name = "StorageLens"
    static let version = "0.1.1"
    static let author = "Glaydston Veloso"
    static let repository = URL(string: "https://github.com/glaydston/storagelens")!
    static let license = "MIT"

    static var copyright: String { "© 2026 \(author) · \(license) licensed" }

    /// e.g. "StorageLens 1.2.3 · Ada Lovelace"
    static var summary: String { "\(name) \(version) · \(author)" }
}
