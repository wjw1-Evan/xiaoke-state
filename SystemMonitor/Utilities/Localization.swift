import Foundation
import os.log

/// Localization manager for multi-language support
class Localization {
    static let shared = Localization()

    private var bundle: Bundle?
    private let overrideKey = "languageOverride"
    private let logger = Logger(subsystem: "com.systemmonitor", category: "Localization")
    private var activeLanguage: String = "en"

    #if SWIFT_PACKAGE
        private let spmBundle: Bundle? = .module
    #else
        private let spmBundle: Bundle? = nil
    #endif

    private init() {
        resolveBundle()
    }

    /// Refresh bundle after language override changes
    func refreshBundle() {
        resolveBundle()
    }

    private func resolveBundle() {
        // Find the localization bundle
        let language = getCurrentLanguage()
        activeLanguage = language
        // Try matching lproj in main bundle first, then SwiftPM bundle (if present), case-insensitive
        let candidateBundles: [Bundle?] = [Bundle.main, spmBundle]
        if let resolved = candidateBundles.compactMap({ root -> Bundle? in
            guard let root else { return nil }
            if let bundle = findLprojBundle(language, in: root) {
                logger.debug(
                    "Localization resolved to \(language, privacy: .public) at path: \(bundle.bundlePath, privacy: .public)"
                )
                return bundle
            }
            return nil
        }).first {
            self.bundle = resolved
        } else {
            // Fallback: Base.lproj if present (main then spm)
            if let fallback = candidateBundles.compactMap({ root -> Bundle? in
                guard let root else { return nil }
                if let basePath = root.path(forResource: "Base", ofType: "lproj"),
                    let baseBundle = Bundle(path: basePath)
                {
                    logger.debug(
                        "Localization fell back to Base.lproj at path: \(basePath, privacy: .public)"
                    )
                    return baseBundle
                }
                return nil
            }).first {
                self.bundle = fallback
            } else {
                // Fallback to main bundle (or spm if main unavailable)
                self.bundle = Bundle.main
                if self.bundle == Bundle.main {
                    logger.debug("Localization fell back to main bundle (no specific lproj found)")
                } else {
                    logger.debug(
                        "Localization fell back to default bundle (no specific lproj found)")
                }
            }
        }
    }

    /// Get current system language
    private func getCurrentLanguage() -> String {
        // 0) User override from preferences (UserDefaults)
        if let override = UserDefaults.standard.string(forKey: overrideKey), override != "auto" {
            return override
        }
        func resourceExists(for code: String) -> Bool {
            if findLprojBundle(code, in: Bundle.main) != nil { return true }
            if let spm = spmBundle, findLprojBundle(code, in: spm) != nil { return true }
            return false
        }

        for language in Locale.preferredLanguages {
            // 1) Try exact match (e.g., "zh-Hans-CN" won't exist, but sometimes full tag may be present)
            if resourceExists(for: language) { return language }

            // 2) Try language-script (e.g., zh-Hans / zh-Hant)
            // Parse BCP-47 language tag manually to avoid deprecated Locale APIs
            let normalized = language.replacingOccurrences(of: "_", with: "-")
            let parts = normalized.split(separator: "-")
            let langCode = parts.first.map { String($0).lowercased() }

            // Detect script (Hans/Hant) and region (CN/TW/HK/MO/SG)
            var scriptCode: String? = nil
            var regionCode: String? = nil
            for part in parts.dropFirst() {
                let p = String(part)
                let lower = p.lowercased()
                if lower == "hans" || lower == "hant" {
                    scriptCode = lower.capitalized  // Hans or Hant
                } else if p.count == 2 {  // Region usually 2 letters, keep original case
                    regionCode = lower
                }
            }

            if let langCode = langCode {
                if let scriptCode = scriptCode {
                    let candidate = "\(langCode)-\(scriptCode)"  // e.g., zh-Hans
                    if resourceExists(for: candidate) { return candidate }
                }

                // 2.1) Special handling for Chinese without script but with region
                if langCode == "zh" {
                    let inferredScript =
                        (regionCode == "tw" || regionCode == "hk" || regionCode == "mo")
                        ? "Hant" : "Hans"
                    let candidate = "zh-\(inferredScript)"
                    if resourceExists(for: candidate) { return candidate }
                }

                // 3) Try plain language code (e.g., ja, en)
                if resourceExists(for: langCode) { return langCode }
            }
        }

        // Fallback to English
        return "en"
    }

    private func findLprojBundle(_ code: String, in root: Bundle) -> Bundle? {
        // Try exact code, then lowercase (SwiftPM stores lproj folder lowercased e.g., zh-hans.lproj)
        if let path = root.path(forResource: code, ofType: "lproj"), let b = Bundle(path: path) {
            return b
        }
        let lower = code.lowercased()
        if lower != code,
            let path = root.path(forResource: lower, ofType: "lproj"),
            let b = Bundle(path: path)
        {
            return b
        }
        return nil
    }

    /// Localize a string
    func localizedString(_ key: String, comment: String = "") -> String {
        // Pick a fallback bundle in order: current language bundle, main bundle, SPM bundle
        let fallbackFromMain = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        let fallbackFromSPM =
            spmBundle?.localizedString(forKey: key, value: fallbackFromMain, table: nil)
            ?? fallbackFromMain
        let fallbackValue = fallbackFromSPM
        let result =
            bundle?.localizedString(forKey: key, value: fallbackValue, table: nil)
            ?? fallbackValue

        // Diagnostics: log missing keys to help identify packaging issues
        if result == key {
            logger.debug(
                "Missing localization for key=\(key, privacy: .public), lang=\(self.activeLanguage, privacy: .public), available=\(self.allAvailableLocalizations(), privacy: .public)"
            )
        } else if result == fallbackValue && self.activeLanguage != "en" {
            logger.debug(
                "Localization fallback for key=\(key, privacy: .public) to base language; active=\(self.activeLanguage, privacy: .public)"
            )
        }
        return result
    }

    /// Format a localized string with arguments
    func localizedString(_ key: String, _ arguments: CVarArg..., comment: String = "") -> String {
        let format = localizedString(key, comment: comment)
        return String(format: format, arguments: arguments)
    }
}

/// Convenience function for localization
func NSLocalizedString(_ key: String, comment: String = "") -> String {
    return Localization.shared.localizedString(key, comment: comment)
}

/// Expose diagnostics for localization state
extension Localization {
    func diagnostics() -> (
        activeLanguage: String, bundlePath: String?, available: [String], preferred: [String]
    ) {
        let available = allAvailableLocalizations()
        let preferred = Bundle.main.preferredLocalizations
        var path: String? = nil
        let lang = activeLanguage
        if let p = Bundle.main.path(forResource: lang, ofType: "lproj") { path = p }
        if path == nil, let spm = spmBundle,
            let p = spm.path(forResource: lang, ofType: "lproj")
        {
            path = p
        }
        return (activeLanguage, path, available, preferred)
    }

    private func allAvailableLocalizations() -> [String] {
        var set = Set(Bundle.main.localizations)
        if let spm = spmBundle {
            set.formUnion(spm.localizations)
        }
        return Array(set).sorted()
    }
}
