import AppKit
import XCTest
@testable import Sensveil

@MainActor
final class OverlayMaterialContentTests: XCTestCase {
    func testAllLevelsUsePersistentAnchorAndDistinctSelectedMaterials() {
        let content = OverlayMaterialContent(frame: CGRect(x: 0, y: 0, width: 656, height: 608))
        let tierEffect = content.tierEffect
        let guardLabel = content.guardLabel
        let pairs: [(BlurLevel, NSVisualEffectView.Material)] = [(.standard, .hudWindow), (.enhanced, .popover), (.strongest, .underWindowBackground), (.enhanced, .popover), (.standard, .hudWindow)]
        for (level, material) in pairs {
            content.apply(settings: OverlaySettings(blurLevel: level, showsProtectionLabel: true), protectionStatus: .cannotProtect("unverified"))
            XCTAssertEqual(content.material, .popover)
            XCTAssertEqual(content.tierEffect.material, material)
            XCTAssertTrue(content.tierEffect === tierEffect)
            XCTAssertTrue(content.guardLabel === guardLabel)
            XCTAssertTrue(tierEffect.superview === content)
            XCTAssertTrue(guardLabel.superview === content)
            XCTAssertEqual(content.subviews.count, 3)
            XCTAssertEqual(content.alphaValue, 1)
            XCTAssertEqual(content.tierEffect.alphaValue, 1)
            XCTAssertEqual(content.blendingMode, .behindWindow)
            XCTAssertEqual(content.tierEffect.blendingMode, .behindWindow)
        }
    }

    func testOnlyVerifiedProtectionShowsCenteredNonInteractiveLabel() {
        let content = OverlayMaterialContent(frame: CGRect(x: 0, y: 0, width: 656, height: 608))
        for status in [ProtectionStatus.foreground, .paused, .outsideSchedule, .cannotProtect("unverified"), .partialFailure(["failed"])] {
            content.apply(settings: .defaults, protectionStatus: status)
            XCTAssertTrue(content.guardLabel.isHidden)
        }
        content.apply(settings: .defaults, protectionStatus: .protected)
        XCTAssertFalse(content.guardLabel.isHidden)
        XCTAssertEqual(content.guardLabel.frame.midX, content.bounds.midX, accuracy: 0.01)
        XCTAssertEqual(content.guardLabel.frame.midY, content.bounds.midY, accuracy: 0.01)
        XCTAssertNil(content.hitTest(CGPoint(x: content.bounds.midX, y: content.bounds.midY)))
    }

    func testLabelToggleAndSmallWindowLeaveMaterialsIntact() {
        let content = OverlayMaterialContent(frame: CGRect(x: 0, y: 0, width: 656, height: 608))
        content.apply(settings: OverlaySettings(blurLevel: .enhanced, showsProtectionLabel: false), protectionStatus: .protected)
        XCTAssertTrue(content.guardLabel.isHidden)
        XCTAssertEqual(content.tierEffect.material, .popover)
        content.apply(settings: .defaults, protectionStatus: .protected)
        content.setFrameSize(CGSize(width: 60, height: 40))
        content.layout()
        XCTAssertTrue(content.guardLabel.isHidden)
        XCTAssertEqual(content.tierEffect.frame, content.bounds)
        content.setFrameSize(CGSize(width: 700, height: 500))
        content.layout()
        XCTAssertFalse(content.guardLabel.isHidden)
        XCTAssertEqual(content.guardLabel.frame.midX, 350, accuracy: 0.01)
        XCTAssertEqual(content.guardLabel.frame.midY, 250, accuracy: 0.01)
    }

    func testEntryKeepsOpaqueStrongestSafetyMaterialAndPersistentAnchor() {
        let content = OverlayMaterialContent(frame: CGRect(x: 0, y: 0, width: 656, height: 608))
        content.apply(settings: .defaults, protectionStatus: .protected)
        content.beginProtectionTransition(reduceMotion: false)

        XCTAssertTrue(content.isProtectionTransitionRunning)
        XCTAssertEqual(content.material, .popover)
        XCTAssertEqual(content.alphaValue, 1)
        XCTAssertEqual(content.layer?.opacity, 1)
        XCTAssertEqual(content.safetyEffect.material, .underWindowBackground)
        XCTAssertEqual(content.safetyEffect.alphaValue, 1)
        XCTAssertEqual(content.safetyEffect.layer?.opacity, 1)
        XCTAssertFalse(content.safetyEffect.isHidden)
        XCTAssertTrue(content.subviews[0] === content.safetyEffect)
        XCTAssertTrue(content.subviews[1] === content.tierEffect)
        XCTAssertEqual(content.tierEffect.layer?.opacity, 1)
        let animation = content.tierEffect.layer?.animation(forKey: "protectionEntry") as? CABasicAnimation
        XCTAssertEqual(animation?.keyPath, "opacity")
        XCTAssertEqual(animation?.fromValue as? Float, 0)
        XCTAssertEqual(animation?.toValue as? Float, 1)
        XCTAssertEqual(animation?.duration, 0.2)
        content.cancelProtectionTransition()
    }

    func testReducedMotionUsesFinalCompositionImmediately() {
        let content = OverlayMaterialContent(frame: .zero)
        content.beginProtectionTransition(reduceMotion: true)
        XCTAssertFalse(content.isProtectionTransitionRunning)
        XCTAssertTrue(content.safetyEffect.isHidden)
        XCTAssertEqual(content.tierEffect.layer?.opacity, 1)
        XCTAssertNil(content.tierEffect.layer?.animation(forKey: "protectionEntry"))
    }

    func testCancelledCompletionCannotFinishRestartedTransition() async throws {
        let content = OverlayMaterialContent(frame: .zero)
        content.beginProtectionTransition(reduceMotion: false)
        try await Task.sleep(for: .milliseconds(130))
        content.cancelProtectionTransition()
        XCTAssertFalse(content.isProtectionTransitionRunning)
        XCTAssertTrue(content.safetyEffect.isHidden)
        XCTAssertNil(content.tierEffect.layer?.animation(forKey: "protectionEntry"))
        content.beginProtectionTransition(reduceMotion: false)
        try await Task.sleep(for: .milliseconds(110))
        XCTAssertTrue(content.isProtectionTransitionRunning)
        XCTAssertFalse(content.safetyEffect.isHidden)
        try await Task.sleep(for: .milliseconds(130))
        XCTAssertFalse(content.isProtectionTransitionRunning)
        XCTAssertTrue(content.safetyEffect.isHidden)
        XCTAssertEqual(content.tierEffect.layer?.opacity, 1)
        XCTAssertNil(content.tierEffect.layer?.animation(forKey: "protectionEntry"))
    }

    func testLayoutAndLabelChangesPreserveTransitionButTierChangeCancels() {
        let content = OverlayMaterialContent(frame: CGRect(x: 0, y: 0, width: 656, height: 608))
        content.apply(settings: .defaults, protectionStatus: .cannotProtect("unverified"))
        content.beginProtectionTransition(reduceMotion: false)
        content.setFrameSize(CGSize(width: 800, height: 700))
        content.layout()
        XCTAssertEqual(content.safetyEffect.frame, content.bounds)
        XCTAssertEqual(content.tierEffect.frame, content.bounds)
        XCTAssertTrue(content.guardLabel.isHidden)
        content.apply(settings: OverlaySettings(blurLevel: .standard, showsProtectionLabel: false), protectionStatus: .protected)
        XCTAssertTrue(content.isProtectionTransitionRunning)
        XCTAssertTrue(content.guardLabel.isHidden)
        content.apply(settings: OverlaySettings(blurLevel: .enhanced, showsProtectionLabel: true), protectionStatus: .protected)
        XCTAssertFalse(content.isProtectionTransitionRunning)
        XCTAssertTrue(content.safetyEffect.isHidden)
        XCTAssertEqual(content.tierEffect.material, .popover)
        XCTAssertFalse(content.guardLabel.isHidden)
    }

    func testEveryDurationAndOffControlEntryAnimation() {
        let content = OverlayMaterialContent(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        for choice in ProtectionTransition.allCases {
            content.apply(settings: .init(blurLevel: .standard, showsProtectionLabel: true, protectionTransition: choice), protectionStatus: .protected)
            content.beginProtectionTransition(reduceMotion: false)
            let animation = content.tierEffect.layer?.animation(forKey: "protectionEntry")
            if let duration = choice.duration {
                XCTAssertTrue(content.isProtectionTransitionRunning)
                XCTAssertEqual(animation?.duration, duration)
                XCTAssertFalse(content.safetyEffect.isHidden)
            } else {
                XCTAssertFalse(content.isProtectionTransitionRunning)
                XCTAssertNil(animation)
                XCTAssertTrue(content.safetyEffect.isHidden)
            }
            XCTAssertEqual(content.alphaValue, 1)
            content.cancelProtectionTransition()
        }
    }

    func testDurationChangeCancelsRunningEntryWithoutRemovingFinalBlur() {
        let content = OverlayMaterialContent(frame: .zero)
        content.beginProtectionTransition(reduceMotion: false)
        XCTAssertTrue(content.isProtectionTransitionRunning)
        content.apply(settings: .init(blurLevel: .standard, showsProtectionLabel: true, protectionTransition: .ms800), protectionStatus: .protected)
        XCTAssertFalse(content.isProtectionTransitionRunning)
        XCTAssertNil(content.tierEffect.layer?.animation(forKey: "protectionEntry"))
        XCTAssertEqual(content.tierEffect.layer?.opacity, 1)
        XCTAssertEqual(content.material, .popover)
    }
}
