import AppKit
import PoCCore

/// Finite self-owned synthetic-window check; it never loads user configuration or captures pixels.
@MainActor
public enum GuardLabelValidation {
    public static func run() async -> Int32 {
        let screens = NSScreen.screens
        guard !screens.isEmpty,
              screens.allSatisfy({ $0.backingScaleFactor == 1 || $0.backingScaleFactor == 2 }),
              MaterialAcceptanceEnvironment.current.isAccepted else {
            print("GUARD unsupported acceptance environment")
            return 2
        }
        var result: Int32 = 0
        for (index, screen) in screens.enumerated() {
            print("GUARD display=\(index + 1)/\(screens.count) scale=\(screen.backingScaleFactor)")
            if await run(on: screen, screens: screens) != 0 { result = 1 }
        }
        return result
    }

    private static func run(on screen: NSScreen, screens: [NSScreen]) async -> Int32 {
        guard let primaryScreen = screens.first else { return 2 }
        let target = NSWindow(contentRect: CGRect(x: screen.visibleFrame.minX + 100,
            y: screen.visibleFrame.minY + 100, width: 420, height: 280),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        target.isReleasedWhenClosed = false
        target.title = "SYNTHETIC GUARD VALIDATION"
        let text = NSTextField(labelWithString: "Synthetic account 000-0000-0001")
        text.frame = CGRect(x: 30, y: 80, width: 350, height: 40)
        target.contentView?.addSubview(text)
        target.orderFront(nil)
        var panels: [MaterialPanel] = []
        let coordinator = MaterialOverlayCoordinator(makePanel: { frame in
            let panel = MaterialPanel(frame: frame)
            panels.append(panel)
            return panel
        })
        defer { coordinator.removeAll(); target.close() }
        let key = WindowKey(process: .init(pid: ProcessInfo.processInfo.processIdentifier, generation: 1), cgWindowID: UInt32(target.windowNumber))
        let layout = ScreenLayout(primaryScreenFrame: primaryScreen.frame, screenFrames: screens.map(\.frame))
        func candidate() -> WindowCandidate {
            WindowCandidate(key: key, bounds: CoordinateTransform.appKitRect(from: target.frame,
                primaryScreenFrame: primaryScreen.frame), isOnScreen: target.isVisible, layer: 0)
        }
        var checks = 0
        var passed = 0
        var transitionChoice = ProtectionTransition.ms200
        func check(_ name: String, _ condition: Bool) {
            checks += 1
            if condition { passed += 1 }
            print("GUARD \(name) passed=\(condition)")
        }
        func reconcile() -> OverlayObservation? {
            coordinator.reconcile([key: .attemptBlur], windows: [candidate()], screenLayout: layout)[key]
        }
        func labelVisible() -> Bool { panels.last.map { !$0.materialContent.guardLabel.isHidden } ?? false }
        func validateNaturalCheck() async -> Bool {
            let attempts = Int(ceil((transitionChoice.duration ?? 0) / 0.15)) + 5
            for _ in 0..<attempts {
                try? await Task.sleep(for: .milliseconds(150))
                switch reconcile() {
                case .protected: return true
                case .failed(let reason):
                    print("GUARD naturalCheck failed=\(reason)")
                    continue
                default:
                    print("GUARD naturalCheck pending")
                    continue
                }
            }
            return false
        }
        if case .requestSubmitted = reconcile() { check("firstRequestHidden", !labelVisible()) }
        else { check("firstRequestHidden", false) }
        if let panel = panels.last {
            let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            check("entryStartsWithFullStrongestMaterial", reduced || (panel.alphaValue == 1
                && panel.materialContent.material == .popover
                && panel.materialContent.safetyEffect.material == .underWindowBackground
                && !panel.materialContent.safetyEffect.isHidden
                && panel.materialContent.isProtectionTransitionRunning))
        }
        check("naturalCheckShowsLabel", await validateNaturalCheck() && labelVisible())
        for level in [BlurLevel.enhanced, .strongest, .standard] {
            let count = panels.count
            coordinator.setSettings(.init(blurLevel: level, showsProtectionLabel: true))
            check("tierChangeInvalidatesLabel", !labelVisible() && count == panels.count)
            _ = reconcile()
            check("tierRecheckedShowsLabel", await validateNaturalCheck() && labelVisible())
        }
        coordinator.setSettings(.init(blurLevel: .standard, showsProtectionLabel: false))
        check("toggleHidesWithoutRemoval", !labelVisible() && !coordinator.overlayKeys.isEmpty)
        coordinator.setSettings(.defaults)
        check("toggleRestoresVerifiedLabel", labelVisible())
        target.setFrameOrigin(CGPoint(x: target.frame.minX + 25, y: target.frame.minY + 15))
        _ = reconcile()
        check("movedLabelWaitsForValidation", !labelVisible())
        check("movedLabelFollows", await validateNaturalCheck() && labelVisible())
        target.setFrame(CGRect(origin: target.frame.origin, size: CGSize(width: 500, height: 350)), display: true)
        _ = reconcile()
        check("resizedLabelWaitsForValidation", !labelVisible())
        check("resizedLabelFollows", await validateNaturalCheck() && labelVisible())
        if let content = panels.last?.materialContent {
            check("centeredAndNoninteractive", abs(content.guardLabel.frame.midX - content.bounds.midX) < 0.01
                && abs(content.guardLabel.frame.midY - content.bounds.midY) < 0.01
                && content.hitTest(CGPoint(x: content.bounds.midX, y: content.bounds.midY)) == nil)
        }
        let protectedPanel = panels.last
        _ = coordinator.reconcile([key: .remove], windows: [candidate()], screenLayout: layout,
            foregroundPID: key.process.pid)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        check("foregroundExitHidesLabelAndRetires", !labelVisible()
            && coordinator.overlayKeys.isEmpty && (reduced || coordinator.retiringKeys.contains(key)))
        _ = reconcile()
        check("rapidReentryCancelsOldExit", coordinator.retiringKeys.isEmpty && protectedPanel?.isVisible == false)
        check("rapidReentryValidatesNewPanel", await validateNaturalCheck() && labelVisible())
        for choice in ProtectionTransition.allCases {
            transitionChoice = choice
            coordinator.removeAll()
            coordinator.setSettings(.init(blurLevel: .standard, showsProtectionLabel: true, protectionTransition: choice))
            _ = reconcile()
            if let content = panels.last?.materialContent {
                let animation = content.tierEffect.layer?.animation(forKey: "protectionEntry")
                check("selectedEntryDuration-\(choice.rawValue)", reduced || animation?.duration == choice.duration)
            }
            check("selectedDurationProtects-\(choice.rawValue)", await validateNaturalCheck() && labelVisible())
            _ = coordinator.reconcile([key: .remove], windows: [candidate()], screenLayout: layout,
                foregroundPID: key.process.pid)
            if choice == .off { check("offExitIsImmediate", coordinator.retiringKeys.isEmpty) }
            try? await Task.sleep(for: .seconds((choice.duration ?? 0) + 0.15))
            check("selectedExitCompletes-\(choice.rawValue)", coordinator.retiringKeys.isEmpty)
        }
        _ = coordinator.reconcile([key: .remove], windows: [candidate()], screenLayout: layout)
        check("withdrawalRemovesPanel", coordinator.overlayKeys.isEmpty && panels.allSatisfy { !$0.isVisible })
        print("GUARD checks=\(checks) passed=\(passed); synthetic runtime only, no pixel capture")
        return checks == passed ? 0 : 1
    }
}
