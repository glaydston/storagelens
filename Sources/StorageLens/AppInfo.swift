import Foundation

/// Single source of truth for the app's identity.
///
/// `Scripts/build-app.sh` reads `version` out of this file when it writes
/// Info.plist, so bumping it here is the only place a release version changes.
enum AppInfo {
    static let name = "StorageLens"
    static let version = "0.1.0"
    static let author = "Glaydston Veloso"
    static let repository = URL(string: "https://github.com/glaydston/storagelens")!
    static let license = "MIT"

    static var copyright: String { "© 2026 \(author) · \(license) licensed" }

    /// "StorageLens 0.1.0 · Glaydston Veloso"
    static var summary: String { "\(name) \(version) · \(author)" }
}
