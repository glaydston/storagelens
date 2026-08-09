import AppKit
import SwiftUI
import StorageLensKit

/// Colors for the capacity bar and the category lists.
///
/// A hue belongs to a *group*, not to a size rank, so a category keeps its
/// color when a rescan reorders the list. The slots are taken in fixed order
/// from a palette validated for colorblind separation and contrast in both
/// appearances; there are five groups and eight slots, so nothing is ever
/// recycled onto a second meaning.
enum CategoryPalette {
    static func color(for group: CleanupRule.Group) -> Color {
        switch group {
        case .system: slot1
        case .developer: slot2
        case .packageManagers: slot3
        case .applications: slot4
        case .large: slot5
        }
    }

    // Slot n: light / dark step of the same hue, chosen for each surface.
    static let slot1 = dynamic(light: 0x2A78D6, dark: 0x3987E5) // blue
    static let slot2 = dynamic(light: 0xEB6834, dark: 0xD95926) // orange
    static let slot3 = dynamic(light: 0x1BAF7A, dark: 0x199E70) // aqua
    static let slot4 = dynamic(light: 0xEDA100, dark: 0xC98500) // yellow
    static let slot5 = dynamic(light: 0xE87BA4, dark: 0xD55181) // magenta

    /// Used space StorageLens didn't scan — documents, apps, system files.
    /// Neutral on purpose: it isn't a category, it's the remainder.
    static let otherUsed = dynamic(light: 0xB8B8B4, dark: 0x6B6B67)

    /// Empty space. Reads as the track the segments sit in.
    static let free = dynamic(light: 0xE6E6E2, dark: 0x333331)

    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(rgb: Int) {
        self.init(
            srgbRed: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
