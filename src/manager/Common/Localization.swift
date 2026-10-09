/* SPDX-License-Identifier: MIT */
/* Localization.swift - Multi-language support (English / Deutsch) */

import Foundation

enum Language: String {
    case en = "en"
    case de = "de"
}

class Localization {
    static var current: Language {
        get {
            let saved = UserDefaults.standard.string(forKey: "app_language") ?? "en"
            return Language(rawValue: saved) ?? .en
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "app_language")
        }
    }

    static func tr(en: String, de: String) -> String {
        return (current == .en) ? en : de
    }
}
