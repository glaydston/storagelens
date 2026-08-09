import Foundation

/// Human readable byte sizes, using the same base-1000 convention Finder uses.
public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        // ByteCountFormatter renders 0 as "Zero KB", which reads oddly in a
        // column of numbers.
        guard bytes > 0 else { return "0 KB" }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: max(0, bytes))
    }
}
