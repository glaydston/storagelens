import Foundation

/// Looks a string up in the app bundle's `Localizable.strings`.
///
/// Keys *are* the English source strings, so an untranslated key falls back to
/// en-US on its own: `NSLocalizedString` returns the key it was handed when a
/// table has no entry for it. That also keeps the call sites readable — you can
/// see the English text where it's used.
///
/// Views call this rather than relying on SwiftUI's implicit
/// `LocalizedStringKey` lookup, so that strings built from variables (category
/// titles, sizes, counts) localize the same way literals do.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = NSLocalizedString(key, bundle: .main, comment: "")
    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: .current, arguments: arguments)
}

/// Plural-aware lookup, backed by `Localizable.stringsdict`.
///
/// Kept separate from `L` so it's obvious at the call site which strings carry
/// grammatical number — "1 item" vs "2 itens" is a per-language rule, not a
/// formatting detail.
func LPlural(_ key: String, _ count: Int) -> String {
    String(format: NSLocalizedString(key, bundle: .main, comment: ""),
           locale: .current,
           count)
}
