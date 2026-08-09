import AppKit
import SwiftUI

@main
struct StorageLensApp: App {
    @State private var model = ScanModel()

    init() {
        // `StorageLens --snapshot <path.png> [--dark]` renders the Overview
        // from preview data and exits. Used to regenerate the README shots.
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--snapshot"), flag + 1 < arguments.count {
            Snapshot.render(
                to: URL(fileURLWithPath: arguments[flag + 1]),
                dark: arguments.contains("--dark")
            )
        }
    }

    var body: some Scene {
        WindowGroup(AppInfo.name) {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
                .task {
                    if model.scans.isEmpty { model.rescan() }
                }
        }
        .defaultSize(width: 1080, height: 700)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L("About %@", AppInfo.name)) { showAboutPanel() }
            }
            CommandGroup(after: .newItem) {
                Button(L("Rescan")) { model.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
                Button(L("Open Trash")) { model.revealTrash() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button(L("%@ on GitHub", AppInfo.name)) {
                    NSWorkspace.shared.open(AppInfo.repository)
                }
            }
        }
    }

    private func showAboutPanel() {
        let credits = NSMutableAttributedString(
            string: L("Review disk usage and reclaim space from caches, logs and the Trash.") + "\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        credits.append(NSAttributedString(
            string: AppInfo.repository.absoluteString,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .link: AppInfo.repository,
            ]
        ))

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: AppInfo.version,
            .credits: credits,
            .init(rawValue: "Copyright"): AppInfo.copyright,
        ])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
