import Foundation
import Testing
@testable import StorageLensKit

@Suite("SafetyGuard")
struct SafetyGuardTests {
    let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")

    @Test("accepts a direct child of an allowed root")
    func acceptsChild() throws {
        try SafetyGuard.validate(root.appendingPathComponent("com.example.app"), allowedRoots: [root])
    }

    @Test("accepts a nested descendant")
    func acceptsDescendant() throws {
        try SafetyGuard.validate(root.appendingPathComponent("a/b/c"), allowedRoots: [root])
    }

    @Test("rejects the allowed root itself")
    func rejectsRoot() {
        #expect(throws: SafetyError.isAllowedRoot(root.standardizedFileURL)) {
            try SafetyGuard.validate(root, allowedRoots: [root])
        }
    }

    @Test("rejects a sibling that merely shares a name prefix")
    func rejectsPrefixSibling() {
        let sibling = URL(fileURLWithPath: root.path + "Extra/file")
        #expect(throws: (any Error).self) {
            try SafetyGuard.validate(sibling, allowedRoots: [root])
        }
    }

    @Test("rejects paths outside every allowed root")
    func rejectsOutside() {
        #expect(throws: (any Error).self) {
            try SafetyGuard.validate(
                URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/taxes.pdf"),
                allowedRoots: [root]
            )
        }
    }

    @Test("rejects protected system locations", arguments: [
        "/System/Library/Frameworks/Foo.framework",
        "/usr/local/bin/tool",
        "/Applications/Safari.app",
    ])
    func rejectsProtected(path: String) {
        let url = URL(fileURLWithPath: path)
        #expect(throws: (any Error).self) {
            try SafetyGuard.validate(url, allowedRoots: [URL(fileURLWithPath: "/")])
        }
    }

    @Test("rejects shallow paths")
    func rejectsShallow() {
        #expect(throws: (any Error).self) {
            try SafetyGuard.validate(
                URL(fileURLWithPath: "/Users/someone"),
                allowedRoots: [URL(fileURLWithPath: "/Users")]
            )
        }
    }

    @Test("a symlinked parent directory cannot smuggle a path out of the allow-list")
    func rejectsSymlinkEscape() throws {
        let sandbox = try TempTree()
        let allowed = try sandbox.directory("allowed")
        let elsewhere = try sandbox.directory("elsewhere")
        try sandbox.file("elsewhere/secret.txt", bytes: 16)

        // allowed/link -> elsewhere, so allowed/link/secret.txt *looks* contained.
        try FileManager.default.createSymbolicLink(
            at: allowed.appendingPathComponent("link"),
            withDestinationURL: elsewhere
        )

        #expect(throws: (any Error).self) {
            try SafetyGuard.validate(
                allowed.appendingPathComponent("link/secret.txt"),
                allowedRoots: [allowed]
            )
        }
    }

    @Test("a symlink is validated as the link itself, not as its target")
    func validatesLinkNotTarget() throws {
        let sandbox = try TempTree()
        let allowed = try sandbox.directory("allowed")
        try FileManager.default.createSymbolicLink(
            at: allowed.appendingPathComponent("shortcut"),
            withDestinationURL: URL(fileURLWithPath: "/System/Library")
        )

        // Removing the link is fine; it must not resolve to /System/Library.
        try SafetyGuard.validate(allowed.appendingPathComponent("shortcut"), allowedRoots: [allowed])
    }
}
