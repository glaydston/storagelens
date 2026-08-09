import Foundation

/// Error text surfaces in the UI, so it localizes like everything else.
///
/// The table lives in the *app* bundle rather than a resource bundle of its
/// own: this library is only ever loaded by StorageLens, and an untranslated
/// key falls back to the English source string.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = NSLocalizedString(key, bundle: .main, comment: "")
    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: .current, arguments: arguments)
}
