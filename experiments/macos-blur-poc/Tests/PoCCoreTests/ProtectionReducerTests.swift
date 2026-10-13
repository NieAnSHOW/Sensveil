import Foundation
import CoreGraphics
import XCTest
@testable import PoCCore

final class ProtectionReducerTests: XCTestCase {
    private let process = ProcessInstance(pid: 42, generation: 1)

    func testAppFocusClearsAllThreeWindows() {
        let windows = (1...3).map { window(id: UInt32($0)) }
        var input = input(windows: windows)
        input.frontmost = process
        XCTAssertEqual(ProtectionReducer.reduce(input), Dictionary(uniqueKeysWithValues: windows.map { ($0.key, .remove) }))
        input.frontmost = ProcessInstance(pid: 43, generation: 1)
        XCTAssertEqual(ProtectionReducer.reduce(input), Dictionary(uniqueKeysWithValues: windows.map { ($0.key, .attemptBlur) }))
    }

    func testPermissionAndSuspensionInvalidateProtection() {
        let target = window(id: 1)
        for permissions: [PermissionState] in [[], [.unknown], [.notGranted], [.granted, .unknown], [.granted, .notGranted]] {
            var value = input(windows: [target])
            value.permissions = permissions
            guard case .cannotProtect(let reason) = ProtectionReducer.reduce(value)[target.key] else {
                XCTFail("Missing permission must prevent a blur attempt")
                continue
            }
            XCTAssertFalse(reason.isEmpty)
        }
        var suspended = input(windows: [target])
        suspended.isSuspended = true
        XCTAssertEqual(ProtectionReducer.reduce(suspended), [target.key: .remove])
        var exited = input(windows: [])
        exited.previousOverlayKeys = [target.key]
        XCTAssertEqual(ProtectionReducer.reduce(exited), [target.key: .remove])
    }

    func testProcessGenerationInvalidatesOldWindow() {
        let old = window(id: 1)
        let new = window(id: 1, process: ProcessInstance(pid: 42, generation: 2))
        var value = input(windows: [new])
        value.previousOverlayKeys = [old.key]
        XCTAssertEqual(ProtectionReducer.reduce(value), [old.key: .remove])
        value.selected = [new.key.process]
        XCTAssertEqual(ProtectionReducer.reduce(value), [old.key: .remove, new.key: .attemptBlur])
    }

    func testInvalidHiddenAndUnselectedWindowsClearPreviousOverlays() {
        let visible = window(id: 1)
        var hidden = window(id: 2)
        hidden.isOnScreen = false
        var invalid = window(id: 3)
        invalid.bounds = .zero
        var elevated = window(id: 4)
        elevated.layer = 1
        let unselected = window(id: 5, process: ProcessInstance(pid: 43, generation: 1))
        var value = input(windows: [visible, hidden, invalid, elevated, unselected])
        value.previousOverlayKeys = [hidden.key, invalid.key, elevated.key, unselected.key]
        XCTAssertEqual(ProtectionReducer.reduce(value), [visible.key: .attemptBlur, hidden.key: .remove, invalid.key: .remove, elevated.key: .remove, unselected.key: .remove])
    }

    func testRevalidationRemovesAllOverlaysBeforeFreshAttempts() {
        let target = window(id: 1)
        let stale = WindowKey(process: process, cgWindowID: 99)
        var value = input(windows: [target])
        value.previousOverlayKeys = [target.key, stale]
        value.requiresRevalidation = true
        XCTAssertEqual(ProtectionReducer.reduce(value), [target.key: .remove, stale: .remove])
        value.requiresRevalidation = false
        XCTAssertEqual(ProtectionReducer.reduce(value), [target.key: .attemptBlur, stale: .remove])
    }

    func testUnknownFocusCannotAttemptBlur() {
        let target = window(id: 1)
        var value = input(windows: [target])
        value.frontmost = nil
        value.previousOverlayKeys = [target.key]
        guard case .cannotProtect(let reason) = ProtectionReducer.reduce(value)[target.key] else {
            return XCTFail("Unknown focus must not attempt blur")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    func testOverflowingGeometryClearsPreviousOverlay() {
        var target = window(id: 1)
        target.bounds = CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0, width: CGFloat.greatestFiniteMagnitude, height: 100)
        var value = input(windows: [target])
        value.previousOverlayKeys = [target.key]
        XCTAssertEqual(ProtectionReducer.reduce(value), [target.key: .remove])
    }

    private func window(id: UInt32, process: ProcessInstance? = nil) -> WindowCandidate {
        WindowCandidate(key: WindowKey(process: process ?? self.process, cgWindowID: id), bounds: CGRect(x: 100, y: 200, width: 500, height: 300), isOnScreen: true, layer: 0)
    }

    func testKnownForegroundPIDWithoutLaunchIdentitySupportsBlurAndUnblur() {
        let window = window(id: 1)
        var value = input(windows: [window])
        value.frontmost = nil
        value.frontmostPID = 200
        XCTAssertEqual(ProtectionReducer.reduce(value)[window.key], .attemptBlur)
        value.frontmostPID = process.pid
        XCTAssertEqual(ProtectionReducer.reduce(value)[window.key], .remove)
    }

    func testInvalidForegroundPIDDoesNotBecomeBackgroundEvidence() {
        let window = window(id: 1)
        var value = input(windows: [window])
        value.frontmost = nil
        for pid: Int32? in [nil, 0, -1] {
            value.frontmostPID = pid
            guard case .cannotProtect = ProtectionReducer.reduce(value)[window.key] else {
                return XCTFail("invalid PID must not supply focus evidence")
            }
        }
    }

    func testObservedProcessIdentityKeepsGenerationPrecedenceOverPIDFallback() {
        let window = window(id: 1)
        var value = input(windows: [window])
        value.frontmost = ProcessInstance(pid: process.pid, generation: process.generation + 1)
        value.frontmostPID = process.pid
        XCTAssertEqual(ProtectionReducer.reduce(value)[window.key], .attemptBlur)
    }

    private func input(windows: [WindowCandidate]) -> ProtectionInput {
        ProtectionInput(frontmost: ProcessInstance(pid: 43, generation: 1), selected: [process], windows: windows, previousOverlayKeys: [], permissions: [.granted], isSuspended: false, requiresRevalidation: false)
    }
}
