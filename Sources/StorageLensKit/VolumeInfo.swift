import Foundation

/// Capacity snapshot for a mounted volume.
public struct VolumeInfo: Sendable, Equatable, Identifiable {
    public var id: String { url.path }

    public let name: String
    public let url: URL
    public let totalCapacity: Int64
    /// Space the OS considers available to an app, including purgeable space it
    /// would evict on demand. This is the number Finder shows as "available".
    public let availableCapacity: Int64

    public init(name: String, url: URL, totalCapacity: Int64, availableCapacity: Int64) {
        self.name = name
        self.url = url
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
    }

    public var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }

    public var usedFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return min(1, max(0, Double(usedCapacity) / Double(totalCapacity)))
    }

    /// Reads capacity for the volume containing `url` (the boot volume by default).
    public static func current(for url: URL = URL(fileURLWithPath: "/")) throws -> VolumeInfo {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        let values = try url.resourceValues(forKeys: keys)
        let available = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)

        return VolumeInfo(
            name: values.volumeName ?? url.lastPathComponent,
            url: url,
            totalCapacity: Int64(values.volumeTotalCapacity ?? 0),
            availableCapacity: available
        )
    }
}
