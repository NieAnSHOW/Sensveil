import XCTest
@testable import Sensveil

final class StatusPresentationTests: XCTestCase {
    func testOnlyVerifiedProtectedStatusDisplaysProtected() {
        XCTAssertEqual(StatusPresentation(.protected).title, "已保护")
        for status: ProtectionStatus in [.cannotProtect("Material request submitted; visual protection is unverified."), .partialFailure(["Relative overlay order was lost"]), .paused, .overFreeLimit, .foreground, .notRunning] {
            XCTAssertNotEqual(StatusPresentation(status).title, "已保护")
        }
    }

    func testUnverifiedMaterialRequestRemainsCannotProtectInChinese() {
        let presentation = StatusPresentation(.cannotProtect("Material request submitted; visual protection is unverified."))
        XCTAssertEqual(presentation.title, "无法保护")
        XCTAssertTrue(presentation.detail.contains("模糊效果尚未验证"))
        XCTAssertFalse(presentation.detail.contains("Material"))
    }

    func testFailuresHaveReadableChineseWithoutRawEngineErrors() {
        XCTAssertEqual(StatusPresentation(.partialFailure(["Relative overlay order was lost"])).title, "部分窗口无法保护")
        XCTAssertTrue(StatusPresentation(.cannotProtect("accessibility permission unavailable")).detail.contains("辅助功能"))
        XCTAssertTrue(StatusPresentation(.cannotProtect("some unknown SDK failure")).detail.contains("无法确认"))
        XCTAssertEqual(StatusPresentation(.paused).title, "已暂停")
        XCTAssertEqual(StatusPresentation(.overFreeLimit).title, "超出免费版数量")
    }
}

@MainActor
final class MenuActionTests: XCTestCase {
    func testPauseAndResumePersistConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(fileURL: directory.appendingPathComponent("config.json"))
        let controller = SensveilController(configurationStore: store, catalog: ApplicationCatalog(applicationDirectories: [], includesRunningApplications: false))
        defer { controller.stopProtection() }

        controller.performMenuAction(.togglePause, openManagement: {}, quit: {})
        XCTAssertTrue(try store.load().isGloballyPaused)
        XCTAssertEqual(controller.pauseActionTitle, "恢复保护")
        controller.performMenuAction(.togglePause, openManagement: {}, quit: {})
        XCTAssertFalse(try store.load().isGloballyPaused)
        XCTAssertEqual(controller.pauseActionTitle, "暂停保护")
    }

    func testMenuRoutesOpenAndQuitWithoutMutatingPause() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let controller = SensveilController(configurationStore: ConfigurationStore(fileURL: directory.appendingPathComponent("config.json")), catalog: ApplicationCatalog(applicationDirectories: [], includesRunningApplications: false))
        var opened = false
        var quit = false
        controller.performMenuAction(.openManagement, openManagement: { opened = true }, quit: {})
        controller.performMenuAction(.quit, openManagement: {}, quit: { quit = true })
        XCTAssertTrue(opened)
        XCTAssertTrue(quit)
        XCTAssertFalse(controller.configuration.isGloballyPaused)
    }

    func testAppTogglePersistsAndLoadFailureLocksMenuMutations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(fileURL: directory.appendingPathComponent("config.json"))
        let app = ProtectedApplication(bundleIdentifier: "com.example.editor", displayName: "Editor")
        try store.save(ProtectionConfiguration(applications: [app]))
        let catalog = ApplicationCatalog(applicationDirectories: [], includesRunningApplications: false)
        let controller = SensveilController(configurationStore: store, catalog: catalog)
        defer { controller.stopProtection() }
        controller.setApplicationEnabled(app, enabled: false)
        XCTAssertFalse(try store.load().applications[0].isEnabled)
        try Data("invalid".utf8).write(to: store.configURL)
        let locked = SensveilController(configurationStore: store, catalog: catalog)
        defer { locked.stopProtection() }
        let originalError = locked.errorMessage
        locked.performMenuAction(.togglePause, openManagement: {}, quit: {})
        locked.setApplicationEnabled(app, enabled: true)
        locked.removeApplication(app)
        XCTAssertTrue(locked.isConfigurationReadOnly)
        XCTAssertFalse(locked.configuration.isGloballyPaused)
        XCTAssertEqual(locked.errorMessage, originalError)
        XCTAssertTrue(originalError?.contains("读取") == true)
    }
}
