import AppKit
import SwiftUI

/// Renders the Overview to a PNG without opening a window, so documentation
/// screenshots can be regenerated from a build rather than captured by hand.
@MainActor
enum Snapshot {
    static func render(to url: URL, dark: Bool) {
        let view = OverviewContent()
            .environment(ScanModel.preview())
            .frame(width: 900, height: 720)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("snapshot: render failed\n".utf8))
            exit(1)
        }

        do {
            try png.write(to: url)
            print("Wrote \(url.path)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
            exit(1)
        }
    }
}
