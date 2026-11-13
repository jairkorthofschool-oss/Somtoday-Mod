import Foundation
import UIKit

/// Stores the Somtoday Mod theme that the injected script reports, so the
/// skeleton loading screen of the next launch matches the chosen theme.
/// Equivalent of the SAVE_THEME native message in the Android-GeckoView app.
enum ThemeStore {
    static let key = "modTheme"

    static func theme(for traits: UITraitCollection?) -> String {
        switch savedTheme {
        case "light", "dark", "night":
            return savedTheme
        default:
            let isDark = traits?.userInterfaceStyle == .dark
            return isDark ? "dark" : "light"
        }
    }

    static var savedTheme: String {
        UserDefaults.standard.string(forKey: key) ?? ""
    }

    static func save(_ theme: String) {
        guard ["light", "dark", "night"].contains(theme) else { return }
        UserDefaults.standard.set(theme, forKey: key)
    }
}
