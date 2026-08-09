# StorageLens

A native SwiftUI app for macOS that shows where your disk space went and
reclaims the parts that are safe to lose — caches, logs, build artifacts, and
the Trash.

Everything it removes goes to the Trash. The only exception is the Trash
itself, which is flagged in the UI and asks for a separate confirmation.

## What it scans

| Group | Included |
| --- | --- |
| System | Trash, `~/Library/Caches`, `~/Library/Logs`, crash reports |
| Developer | Xcode DerivedData / Archives / iOS DeviceSupport, simulator caches, SwiftPM cache |
| Package managers | Homebrew, npm, Yarn, pnpm, pip, uv, Go, Cargo, Gradle, CocoaPods, Deno |
| Applications | Per-app cache folders inside `~/Library/Containers` |
| Needs review | iOS device backups, `~/Downloads`, Mail attachments |

Categories are either **safe** (caches an app rebuilds — pre-selectable with
*Select All Safe*) or **needs review** (real data, never selected for you).

## Requirements

macOS 14 or later, Xcode 16+ / Swift 6 toolchain.

## Build and run

```sh
make test    # 23 tests, no file system side effects outside a temp dir
make app     # assembles build/StorageLens.app
make run     # build + launch
```

Or open `Package.swift` in Xcode and run the `StorageLens` scheme.

The build script signs the app ad-hoc, which is enough to run locally. For
distribution to other Macs you'd sign with a Developer ID certificate and
notarize.

### Full Disk Access

The app is deliberately **not sandboxed** — a sandboxed app can't see
`~/Library/Caches` or the Trash at all. Unprotected locations work right away.
For protected ones (Mail, some app containers), grant Full Disk Access:

> System Settings → Privacy & Security → Full Disk Access → add `StorageLens.app`

The app shows a banner with a button that opens that pane when a scan hits a
folder it couldn't read.

## Safety model

Deleting files is the whole point of the app, so the destructive path is
narrow and covered by tests:

1. **Allow-list.** Every removal is validated against the roots derived from
   the rule catalog. A path outside them is refused even if the UI somehow
   offered it (`SafetyGuard.validate`).
2. **Contents, never the container.** Rules target the *children* of a root.
   The root itself is rejected, so `~/Library/Caches` can be emptied but never
   removed.
3. **Symlinks are removed, not followed.** The parent directory is resolved
   before validation — so `caches/link -> /System` can't smuggle a path past
   the allow-list — while the final component is left unresolved, so a symlink
   is deleted as a link and its target is untouched.
4. **Protected prefixes.** `/System`, `/usr`, `/Applications`, `/private/var/db`
   and friends are rejected unconditionally, as are paths shallower than five
   components.
5. **Trash, not `rm`.** `FileManager.trashItem` everywhere except the Trash
   category, which is `.permanent` and confirms separately.
6. **Nothing happens without a tick.** No auto-clean, no scheduled runs. Sizes
   are measured; removal waits for an explicit selection and a confirmation
   dialog.

Sizes are *allocated size on disk* (`totalFileAllocatedSize`), the same number
Finder reports, so the freed total matches what the volume gauge moves by.
Purgeable space is not counted — macOS reclaims that on its own.

## Layout

```
Sources/StorageLensKit/   scanning, rules, safety, removal — no UI, fully tested
  CleanupRule.swift       the catalog of what's cleanable
  DiskScanner.swift       read-only sizing, concurrent per rule
  SafetyGuard.swift       allow-list validation
  Cleaner.swift           removal, behind an injectable FileOperations
Sources/StorageLens/      SwiftUI app: ScanModel + views
Tests/StorageLensKitTests/
Scripts/build-app.sh      binary -> .app bundle -> ad-hoc signature
Scripts/make-icon.swift   regenerates Resources/AppIcon.icns
```

The logic lives in a library target so it can be tested without launching a UI;
the executable target is only the app shell and views.

## Prior art

Worth knowing about before extending this:
[PureMac](https://github.com/momenbasel/PureMac) (SwiftUI cleaner, the closest
equivalent), [Radix](https://github.com/colinvkim/Radix) (fast disk analyzer),
[MangoDisk](https://github.com/harry0703/MangoDisk) (analyzer plus duplicate
finder).

## License

MIT
