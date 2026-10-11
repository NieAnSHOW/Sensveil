import AppKit
import PoCCore

/// API-stage observations only. Neither case certifies composited pixels.
enum OverlayObservation: Equatable {
    case requestSubmitted
    case failed(reason: String)
}

@MainActor
private final class MaterialPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class MaterialOverlayCoordinator {
    private struct Overlay {
        let panel: MaterialPanel
        let targetBounds: CGRect
    }

    private var overlays: [WindowKey: Overlay] = [:]
    private var orderingFailure: String?

    var overlayKeys: Set<WindowKey> { Set(overlays.keys) }

    init() {}

    func reconcile(_ intents: [WindowKey: OverlayIntent], windows: [WindowCandidate],
                   screenLayout: ScreenLayout) -> [WindowKey: OverlayObservation] {
        var observations: [WindowKey: OverlayObservation] = [:]
        let attempts = Set(intents.compactMap { key, intent in intent == .attemptBlur ? key : nil })
        for key in Set(overlays.keys).subtracting(attempts) { remove(key) }
        for (key, intent) in intents {
            if case .cannotProtect(let reason) = intent { observations[key] = .failed(reason: reason) }
        }
        guard !attempts.isEmpty else { return observations }

        // A system setting asking for opaque backgrounds cannot meet the blur contract.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            removePanels()
            for key in attempts {
                observations[key] = .failed(reason: "Reduce Transparency is enabled; material blur is unavailable")
            }
            return observations
        }

        // Check the previous requests before any re-ordering can conceal a failure.
        // CG metadata can reject an ordering candidate, but cannot approve visual protection.
        if orderingFailure == nil, !overlays.isEmpty {
            orderingFailure = relativeOrderingFailure()
        }
        if let orderingFailure {
            removePanels()
            for key in attempts { observations[key] = .failed(reason: orderingFailure) }
            return observations
        }

        for key in attempts {
            guard let window = windows.first(where: { $0.key == key }), window.isOnScreen,
                  window.layer == 0, valid(window.bounds), key.cgWindowID > 0,
                  valid(screenLayout.primaryScreenFrame) else {
                remove(key)
                observations[key] = .failed(reason: "Validated window geometry or public identity is unavailable")
                continue
            }
            let rect = CoordinateTransform.appKitRect(from: window.bounds,
                                                       primaryScreenFrame: screenLayout.primaryScreenFrame)
            guard screenLayout.screenFrames.contains(where: { valid($0) && $0.intersects(rect) }) else {
                remove(key)
                observations[key] = .failed(reason: "Target does not intersect a validated display")
                continue
            }
            // Moving/resizing expires the prior placement; never animate across exposed content.
            if overlays[key]?.targetBounds != window.bounds { remove(key) }
            if overlays[key] == nil {
                let panel = MaterialPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.ignoresMouseEvents = true
                panel.hidesOnDeactivate = false
                panel.isFloatingPanel = false
                panel.level = .normal
                panel.animationBehavior = .none
                // Candidate behaviors, not proof of full-screen / Stage Manager support.
                panel.collectionBehavior = [.canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
                let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: rect.size))
                effect.autoresizingMask = [.width, .height]
                effect.material = .hudWindow
                effect.state = .active
                effect.blendingMode = .behindWindow
                effect.isEmphasized = false
                panel.contentView = effect
                overlays[key] = Overlay(panel: panel, targetBounds: window.bounds)
            }
            guard let panel = overlays[key]?.panel else { continue }
            panel.setFrame(rect, display: false)
            panel.order(.above, relativeTo: Int(key.cgWindowID))
                observations[key] = .requestSubmitted
        }
        return observations
    }

    func removeAll() {
        removePanels()
        orderingFailure = nil
    }

    private func removePanels() {
        for key in Array(overlays.keys) { remove(key) }
    }

    private func remove(_ key: WindowKey) {
        guard let overlay = overlays.removeValue(forKey: key) else { return }
        overlay.panel.orderOut(nil)
        overlay.panel.close()
    }

    private func relativeOrderingFailure() -> String? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                  kCGNullWindowID) as? [[String: Any]] else {
            return "Public window order metadata is unavailable; relative layering is unverified"
        }
        let orderedIDs = list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        let ownIDs = Set(overlays.values.map { UInt32($0.panel.windowNumber) })
        for (key, overlay) in overlays {
            guard let panelIndex = orderedIDs.firstIndex(of: UInt32(overlay.panel.windowNumber)),
                  let targetIndex = orderedIDs.firstIndex(of: key.cgWindowID), panelIndex < targetIndex else {
                return "Relative overlay order was lost; cannot protect with this material candidate"
            }
            // Own panels may be adjacent for overlapping target windows. An unrelated window
            // between this panel and its target means this candidate could blur that window.
            let between = orderedIDs[(panelIndex + 1)..<targetIndex]
            guard between.allSatisfy({ ownIDs.contains($0) }) else {
                return "An unrelated window is between overlay and target; relative layering failed"
            }
        }
        return nil
    }

    private func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0 &&
            [rect.minX, rect.maxX, rect.minY, rect.maxY, rect.width, rect.height].allSatisfy(\.isFinite)
    }
}

@MainActor
protocol OverlayCoordinating: AnyObject {
    var overlayKeys: Set<WindowKey> { get }
    func reconcile(_ intents: [WindowKey: OverlayIntent], windows: [WindowCandidate], screenLayout: ScreenLayout) -> [WindowKey: OverlayObservation]
    func removeAll()
}

extension MaterialOverlayCoordinator: OverlayCoordinating {}
