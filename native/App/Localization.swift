import Foundation

/// Runtime error strings use the same main-bundle catalog as SwiftUI.
enum AppL10n {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: .main, comment: "")
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}

/// Brand and infrastructure identifiers must never be translated.
enum ProductIdentity {
    static let displayName = "Keine Magie"
    static let defaultServerURL = "https://keinemagie.tinyserve.org"
}
