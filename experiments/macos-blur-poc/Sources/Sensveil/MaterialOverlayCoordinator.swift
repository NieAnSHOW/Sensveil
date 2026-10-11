import AppKit
import PoCCore

/// API-stage observations only. Neither case certifies composited pixels.
enum OverlayObservation: Equatable {
    case requestSubmitted
    case failed(reason: String)
}

@MainActor
protocol MaterialPanelPresenting: AnyObject {
    var windowID: UInt32 { get }
    func submit(frame: CGRect, above targetID: UInt32)
    func remove()
}

@MainActor
private final class MaterialPanel: NSPanel, MaterialPanelPresenting {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    var windowID: UInt32 { UInt32(windowNumber) }

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isFloatingPanel = false
        level = .normal
        animationBehavior = .none
        // Candidate behaviors, not proof of full-screen / Stage Manager support.
        collectionBehavior = [.canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.isEmphasized = false
        contentView = effect
    }

    func submit(frame: CGRect, above targetID: UInt32) {
        setFrame(frame, display: false)
        order(.above, relativeTo: Int(targetID))
    }

    func remove() {
        orderOut(nil)
        close()
    }
}

@MainActor
final class MaterialOverlayCoordinator {
    private struct Overlay {
        let panel: any MaterialPanelPresenting
        let targetBounds: CGRect
    }

    private var overlays: [WindowKey: Overlay] = [:]
    private var orderingFailures: [WindowKey: String] = [:]
    private let makePanel: (CGRect) -> any MaterialPanelPresenting
    private let orderedWindowIDs: () -> [UInt32]?
    private let reduceTransparency: () -> Bool

    var overlayKeys: Set<WindowKey> { Set(overlays.keys) }

    init(makePanel: @escaping (CGRect) -> any MaterialPanelPresenting = { MaterialPanel(frame: $0) },
         orderedWindowIDs: @escaping () -> [UInt32]? = {
             guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
             return list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
         }, reduceTransparency: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }) {
        self.makePanel = makePanel
        self.orderedWindowIDs = orderedWindowIDs
        self.reduceTransparency = reduceTransparency
    }

    func reconcile(_ intents: [WindowKey: OverlayIntent], windows: [WindowCandidate],
                   screenLayout: ScreenLayout) -> [WindowKey: OverlayObservation] {
        var observations: [WindowKey: OverlayObservation] = [:]
        let attempts = Set(intents.compactMap { key, intent in intent == .attemptBlur ? key : nil })
        for key in Set(overlays.keys).subtracting(attempts) { remove(key) }
        // A rejected placement remains rejected while that same target stays selected.
        // Removal/disappearance expires it, so a later window can be rebuilt safely.
        orderingFailures = orderingFailures.filter { attempts.contains($0.key) }
        for (key, intent) in intents {
            if case .cannotProtect(let reason) = intent { observations[key] = .failed(reason: reason) }
        }
        guard !attempts.isEmpty else { return observations }

        if reduceTransparency() {
            removePanels()
            for key in attempts { observations[key] = .failed(reason: "Reduce Transparency is enabled; material blur is unavailable") }
            return observations
        }

        // Check all previous placements from one immutable metadata sample before
        // re-ordering or removing panels can conceal an individual failure.
        if !overlays.isEmpty {
            guard let orderedIDs = orderedWindowIDs() else {
                removePanels()
                for key in attempts { observations[key] = .failed(reason: "Public window order metadata is unavailable; relative layering is unverified") }
                return observations
            }
            let ownIDs = Set(overlays.values.map { $0.panel.windowID })
            for (key, overlay) in overlays {
                if let failure = relativeOrderingFailure(for: key, panelID: overlay.panel.windowID, orderedIDs: orderedIDs, ownIDs: ownIDs) {
                    orderingFailures[key] = failure
                }
            }
        }

        for key in attempts {
            if let failure = orderingFailures[key] {
                remove(key)
                observations[key] = .failed(reason: failure)
                continue
            }
            guard let window = windows.first(where: { $0.key == key }), window.isOnScreen,
                  window.layer == 0, valid(window.bounds), key.cgWindowID > 0,
                  valid(screenLayout.primaryScreenFrame) else {
                remove(key)
                observations[key] = .failed(reason: "Validated window geometry or public identity is unavailable")
                continue
            }
            let rect = CoordinateTransform.appKitRect(from: window.bounds, primaryScreenFrame: screenLayout.primaryScreenFrame)
            guard screenLayout.screenFrames.contains(where: { valid($0) && $0.intersects(rect) }) else {
                remove(key)
                observations[key] = .failed(reason: "Target does not intersect a validated display")
                continue
            }
            // Moving/resizing expires the prior placement; never animate across exposed content.
            if overlays[key]?.targetBounds != window.bounds { remove(key) }
            if overlays[key] == nil { overlays[key] = Overlay(panel: makePanel(rect), targetBounds: window.bounds) }
            overlays[key]?.panel.submit(frame: rect, above: key.cgWindowID)
            observations[key] = .requestSubmitted
        }
        return observations
    }

    func removeAll() {
        removePanels()
        orderingFailures.removeAll()
    }

    private func removePanels() {
        for key in Array(overlays.keys) { remove(key) }
    }

    private func remove(_ key: WindowKey) {
        overlays.removeValue(forKey: key)?.panel.remove()
    }

    private func relativeOrderingFailure(for key: WindowKey, panelID: UInt32, orderedIDs: [UInt32], ownIDs: Set<UInt32>) -> String? {
        guard let panelIndex = orderedIDs.firstIndex(of: panelID),
              let targetIndex = orderedIDs.firstIndex(of: key.cgWindowID), panelIndex < targetIndex else {
            return "Relative overlay order was lost; cannot protect with this material candidate"
        }
        let between = orderedIDs[(panelIndex + 1)..<targetIndex]
        guard between.allSatisfy({ ownIDs.contains($0) }) else {
            return "An unrelated window is between overlay and target; relative layering failed"
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
