import AppKit
import Combine
import XCTest
@testable import Sensveil

@MainActor
final class LocalizationTests: XCTestCase {
    func testSystemLanguageUsesSimplifiedChineseForAllChineseVariants() {
        for identifier in ["zh", "zh-CN", "zh-Hans", "zh-Hant", "zh-TW", "zh-HK", "ZH-Hant-HK", "zh_TW"] {
            XCTAssertEqual(AppLanguage.system.resolvedLanguage(preferredLanguages: [identifier]), "zh-Hans", identifier)
            XCTAssertEqual(L10n.text("保护效果", language: .system, preferredLanguages: [identifier]), "保护效果", identifier)
        }
    }

    func testUnsupportedPrimarySystemLanguageFallsBackToEnglish() {
        for languages in [[], ["en-US"], ["fr-FR"], ["ja-JP", "zh-Hans"], ["zhuang"]] {
            XCTAssertEqual(AppLanguage.system.resolvedLanguage(preferredLanguages: languages), "en")
            XCTAssertEqual(L10n.text("保护效果", language: .system, preferredLanguages: languages), "Protection Effects")
        }
        XCTAssertEqual(AppLanguage.chinese.resolvedLanguage(preferredLanguages: ["en"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.english.resolvedLanguage(preferredLanguages: ["zh"]), "en")
    }

    func testPreferencesPersistIndependentlyAndUnknownValuesFallBackToSystem() throws {
        let suite = "Sensveil.LocalizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("future-language", forKey: LanguagePreferences.storageKey)
        defaults.set("preserve", forKey: "unrelated")
        let preferences = LanguagePreferences(defaults: defaults)
        XCTAssertEqual(preferences.selection, .system)
        preferences.selection = .english
        XCTAssertEqual(LanguagePreferences(defaults: defaults).selection, .english)
        XCTAssertEqual(preferences.locale.identifier, "en")
        preferences.selection = .chinese
        XCTAssertEqual(LanguagePreferences(defaults: defaults).selection, .chinese)
        XCTAssertEqual(preferences.locale.identifier, "zh-Hans")
        preferences.selection = .system
        XCTAssertEqual(LanguagePreferences(defaults: defaults).selection, .system)
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "preserve")
    }

    func testPreferencesWriteBeforePublishingTheIncomingLanguage() throws {
        let suite = "Sensveil.LocalizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = LanguagePreferences(defaults: defaults)
        var savedValues: [String?] = []
        let subscription = preferences.changes.dropFirst().sink { _ in
            savedValues.append(defaults.string(forKey: LanguagePreferences.storageKey))
        }
        preferences.selection = .english
        preferences.selection = .chinese
        XCTAssertEqual(savedValues, ["english", "chinese"])
        withExtendedLifetime(subscription) {}
    }

    func testFormattingPreservesAppIdentityAndVersionValues() {
        XCTAssertEqual(L10n.format("已配置 %d 个应用", language: .english, 5), "5 apps configured")
        XCTAssertEqual(L10n.format("已配置 %d 个应用", language: .chinese, 5), "已配置 5 个应用")
        XCTAssertEqual(L10n.format("添加 %@，%@", language: .english, "写作.app", "com.example.writer"), "Add 写作.app, com.example.writer")
        XCTAssertEqual(L10n.format("版本 %@（%@）", language: .english, "0.1.0", "1"), "Version 0.1.0 (1)")
        XCTAssertEqual(L10n.text("Unknown SDK diagnostic", language: .english), "Unknown SDK diagnostic")
    }

    func testBothCatalogsContainMatchingKeysAndFormattingArguments() throws {
        let chinese = try catalog("zh-Hans")
        let english = try catalog("en")
        XCTAssertEqual(Set(chinese.keys), Set(english.keys))
        let placeholders = try NSRegularExpression(pattern: #"%(?:\d+\$)?[@df]"#)
        for key in chinese.keys {
            let value = try XCTUnwrap(english[key], key)
            XCTAssertFalse(value.isEmpty, key)
            XCTAssertEqual(placeholders.numberOfMatches(in: key, range: NSRange(key.startIndex..., in: key)),
                           placeholders.numberOfMatches(in: value, range: NSRange(value.startIndex..., in: value)), key)
            XCTAssertEqual(L10n.text(key, language: .chinese), chinese[key], key)
            XCTAssertEqual(L10n.text(key, language: .english), value, key)
        }
    }

    func testStatusDetailsTranslateEachFailureAndDoNotExposeEngineDiagnostics() {
        let preferences = LanguagePreferences.shared
        let original = preferences.selection
        defer { preferences.selection = original }
        let status = StatusPresentation(.partialFailure(["Relative overlay order was lost", "Material request submitted; visual protection is unverified."]))
        preferences.selection = .english
        XCTAssertEqual(status.localizedTitle, "Some Windows Cannot Be Protected")
        XCTAssertTrue(status.localizedDetail.contains("Blur has not been verified"))
        XCTAssertTrue(status.localizedDetail.contains("relative window order"))
        XCTAssertFalse(status.localizedDetail.contains("Material request submitted"))
        preferences.selection = .chinese
        XCTAssertEqual(status.localizedTitle, "部分窗口无法保护")
        XCTAssertEqual(status.localizedDetail, status.detail)
    }

    func testLanguageSwitchImmediatelyRebuildsBothMenusAndRetainsPauseBehavior() throws {
        _ = NSApplication.shared
        let preferences = LanguagePreferences.shared
        let original = preferences.selection
        let previousMenu = NSApp.mainMenu
        defer {
            preferences.selection = original
            NSApp.mainMenu = previousMenu
        }
        preferences.selection = .chinese
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = SensveilController(configurationStore: ConfigurationStore(appSupportDirectory: directory),
                                            catalog: ApplicationCatalog(applicationDirectories: [], includesRunningApplications: false))
        defer { controller.stopProtection() }
        let delegate = SensveilAppDelegate(controller: controller)
        delegate.rebuildMenu()
        delegate.installApplicationMenu()
        XCTAssertEqual(delegate.statusMenu?.items.first?.title, "打开 Sensveil")

        preferences.selection = .english
        XCTAssertEqual(delegate.statusMenu?.items.first?.title, "Open Sensveil")
        XCTAssertEqual(NSApp.mainMenu?.items.first?.submenu?.items.first?.title, "About Sensveil")
        XCTAssertEqual(NSApp.mainMenu?.items.last?.title, "Edit")
        let pauseSelector = NSSelectorFromString("togglePauseFromMenu")
        XCTAssertEqual(delegate.statusMenu?.items.first(where: { $0.action == pauseSelector })?.title, "Pause Protection")
        controller.setGlobalPause(true)
        delegate.menuWillOpen(try XCTUnwrap(delegate.statusMenu))
        XCTAssertEqual(delegate.statusMenu?.items.first(where: { $0.action == pauseSelector })?.title, "Resume Protection")

        preferences.selection = .chinese
        XCTAssertEqual(delegate.statusMenu?.items.first?.title, "打开 Sensveil")
        XCTAssertEqual(delegate.statusMenu?.items.first(where: { $0.action == pauseSelector })?.title, "恢复保护")
        XCTAssertEqual(NSApp.mainMenu?.items.first?.submenu?.items.first?.title, "关于 Sensveil")
        XCTAssertTrue(try controller.configurationStore.load().isGloballyPaused)
        XCTAssertTrue(delegate.statusMenu?.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.target === delegate } == true)
    }

    func testSavedReadFailureChangesDisplayLanguageWithoutChangingConfiguration() throws {
        let preferences = LanguagePreferences.shared
        let originalLanguage = preferences.selection
        defer { preferences.selection = originalLanguage }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(appSupportDirectory: directory)
        let originalBytes = Data("not-json".utf8)
        try originalBytes.write(to: store.configURL)
        let controller = SensveilController(configurationStore: store,
                                            catalog: ApplicationCatalog(applicationDirectories: [], includesRunningApplications: false))
        defer { controller.stopProtection() }
        let canonicalError = controller.errorMessage
        preferences.selection = .english
        XCTAssertTrue(controller.localizedErrorMessage?.contains("Unable to read") == true)
        preferences.selection = .chinese
        XCTAssertEqual(controller.localizedErrorMessage, canonicalError)
        XCTAssertEqual(controller.errorMessage, canonicalError)
        XCTAssertTrue(controller.isConfigurationReadOnly)
        XCTAssertEqual(try Data(contentsOf: store.configURL), originalBytes)
    }

    private func catalog(_ language: String) throws -> [String: String] {
        let url = try XCTUnwrap(L10n.resources.url(forResource: "Localizable", withExtension: "strings", subdirectory: "\(language).lproj"))
        return try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    }
}
