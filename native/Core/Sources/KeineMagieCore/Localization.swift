import Foundation

/// Core resources live in the Swift package, not the host application's bundle.
enum CoreL10n {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: .module, comment: "")
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
