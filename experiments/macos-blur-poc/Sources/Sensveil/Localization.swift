import Combine
import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case system, chinese, english
    public var id: String { rawValue }

    public func resolvedLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch self {
        case .chinese: return "zh-Hans"
        case .english: return "en"
        case .system:
            // Use the first system preference. Unsupported languages fall back
            // to English rather than skipping to another preferred language.
            let primary = preferredLanguages.first?.lowercased() ?? ""
            return primary == "zh" || primary.hasPrefix("zh-") || primary.hasPrefix("zh_") ? "zh-Hans" : "en"
        }
    }

    public var locale: Locale { Locale(identifier: resolvedLanguage()) }
}

@MainActor
public final class LanguagePreferences: ObservableObject {
    public static let shared = LanguagePreferences()
    public nonisolated static let storageKey = "Sensveil.interfaceLanguage"
    private let defaults: UserDefaults

    @Published private var storedSelection: AppLanguage
    public var selection: AppLanguage {
        get { storedSelection }
        set {
            guard newValue != storedSelection else { return }
            // Persist before publishing so synchronous AppKit observers and
            // nonisolated presentation reads see the incoming language.
            defaults.set(newValue.rawValue, forKey: Self.storageKey)
            storedSelection = newValue
        }
    }
    var changes: AnyPublisher<AppLanguage, Never> { $storedSelection.eraseToAnyPublisher() }

    public var locale: Locale { selection.locale }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedSelection = AppLanguage(rawValue: defaults.string(forKey: Self.storageKey) ?? "") ?? .system
    }
}

/// Resolves each call from the saved preference so model presentation can be
/// used outside the main actor without a stale translated snapshot.
public enum L10n {
    static let resources = Bundle.module
    public static var language: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: LanguagePreferences.storageKey) ?? "") ?? .system
    }

    public static func text(_ key: String) -> String {
        text(key, language: language)
    }

    public static func text(_ key: String, language: AppLanguage, preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        let identifier = language.resolvedLanguage(preferredLanguages: preferredLanguages)
        guard let path = resources.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: language.resolvedLanguage()), arguments: arguments)
    }

    public static func format(_ key: String, language: AppLanguage, preferredLanguages: [String] = Locale.preferredLanguages, _ arguments: CVarArg...) -> String {
        String(format: text(key, language: language, preferredLanguages: preferredLanguages),
               locale: Locale(identifier: language.resolvedLanguage(preferredLanguages: preferredLanguages)), arguments: arguments)
    }
}
