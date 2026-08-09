import SwiftUI

@main
struct StorageLensApp: App {
    @State private var model = ScanModel()

    var body: some Scene {
        WindowGroup("StorageLens") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
                .task {
                    if model.scans.isEmpty { model.rescan() }
                }
        }
        .defaultSize(width: 1080, height: 700)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rescan") { model.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
