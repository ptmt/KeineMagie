#if targetEnvironment(simulator)
import SwiftUI

/// An explicit simulator-only test override; normal launches use system appearance.
/// AppleInterfaceStyle launch defaults do not reliably change UIKit's traits.
enum SimulatorAppearance {
    static var colorScheme: ColorScheme? {
        guard ProcessInfo.processInfo.environment["KM_SIMULATOR_SESSION_FIXTURE"] == "dictation-local" else { return nil }
        switch ProcessInfo.processInfo.environment["KM_DICTATION_UI_APPEARANCE"] {
        case "Dark": return .dark
        case "Light": return .light
        default: return nil
        }
    }
}
#endif
