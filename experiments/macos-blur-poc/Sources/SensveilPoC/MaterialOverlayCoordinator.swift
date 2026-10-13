import AppKit
import PoCCore

/// API-stage observations only. Neither case certifies composited pixels.
enum OverlayObservation: Equatable {
    case requestSubmitted
    case failed(reason: String)
}

/// Experiment-only material candidate. The three candidates exist so a human-attended
/// session can compare blur strength at 12/24/48pt content; per-tier strength is
/// **unmeasured**, so these names are hypotheses, not declared blur radii.
enum MaterialTier: String, CaseIterable {
    case standard, enhanced, strongest

    /// Public behind-window materials chosen because they plausibly differ in blur strength.
    var material: NSVisualEffectView.Material {
        switch self {
        case .standard: .hudWindow
        case .enhanced: .underWindowBackground
        case .strongest: .popover
        }
    }

    var summary: String { "\(rawValue) = .\(materialName)" }

    private var materialName: String {
        switch self {
        case .standard: "hudWindow"
        case .enhanced: "underWindowBackground"
        case .strongest: "popover"
        }
    }

    /// The state an overlay is composited in before the crossfade starts, and the tier an
    /// aborted transition falls back to. Declared strongest for the experiment; if a
    /// measured session shows another tier blurs more, re-declare this anchor before measuring.
    static let transitionAnchor: MaterialTier = .strongest

    /// Fixed experiment duration. Not a user setting, not a product blur delay.
    static let transitionDuration: TimeInterval = 0.2
}

@MainActor
private final class MaterialPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class MaterialOverlayCoordinator {
    /// Two stacked effect views. The anchor is always present at full strength; the tier view
    /// is crossfaded in on top of it, so no frame is ever composited from an empty/transparent panel.
    private final class Overlay {
        let panel: MaterialPanel
        let targetBounds: CGRect
        let anchorEffect: NSVisualEffectView
        let tierEffect: NSVisualEffectView
        var tier: MaterialTier
        /// A new panel is composited at the anchor tier with the tier view empty, so it needs
        /// exactly one fade-in after it is ordered on screen.
        var pendingFadeIn = true

        init(panel: MaterialPanel, targetBounds: CGRect, anchorEffect: NSVisualEffectView,
             tierEffect: NSVisualEffectView, tier: MaterialTier) {
            self.panel = panel
            self.targetBounds = targetBounds
            self.anchorEffect = anchorEffect
            self.tierEffect = tierEffect
            self.tier = tier
        }
    }

    private var overlays: [WindowKey: Overlay] = [:]
    private var orderingFailure: String?
    private let measurements: MeasurementRecorder

    private(set) var tier: MaterialTier = .standard

    var overlayKeys: Set<WindowKey> { Set(overlays.keys) }

    /// Exact parameters of the prepared experiment, for operator display and docs.
    var parameterSummary: String {
        let anchor = MaterialTier.transitionAnchor
        return "tier \(tier.summary) · anchor \(anchor.summary) · panel borderless+nonactivating, level .normal, "
            + "ignoresMouseEvents, order(.above, relativeTo: target) · both views state .active, "
            + "blendingMode .behindWindow, isEmphasized false"
    }

    var transitionSummary: String {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            return "Reduce Transparency: material path refused (no animation applies; unchanged policy)"
        }
        let milliseconds = Int(MaterialTier.transitionDuration * 1000)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return "Reduce Motion: final tier applied directly, no \(milliseconds)ms crossfade"
        }
        return "\(milliseconds)ms crossfade from the \(MaterialTier.transitionAnchor.rawValue) anchor; "
            + "aborted by focus change, geometry change or removal"
    }

    init(measurements: MeasurementRecorder) { self.measurements = measurements }

    /// Operator-selected candidate. Existing overlays safely re-anchor before they re-crossfade.
    func setTier(_ tier: MaterialTier) {
        guard tier != self.tier else { return }
        self.tier = tier
        for key in Array(overlays.keys) { crossfade(key) }
    }

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
                let anchor = effectView(MaterialTier.transitionAnchor.material, size: rect.size)
                let tierView = effectView(tier.material, size: rect.size)
                // The anchor view is composited at full strength from the first visible frame;
                // the tier view starts empty *on top of it* and is crossfaded in. The panel
                // itself is never faded from alphaValue 0.
                tierView.alphaValue = 0
                anchor.addSubview(tierView)
                panel.contentView = anchor
                overlays[key] = Overlay(panel: panel, targetBounds: window.bounds,
                                        anchorEffect: anchor, tierEffect: tierView, tier: tier)
            }
            guard let overlay = overlays[key] else { continue }
            let started = ContinuousClock.now
            overlay.panel.setFrame(rect, display: false)
            overlay.panel.order(.above, relativeTo: Int(key.cgWindowID))
            if overlay.pendingFadeIn {
                overlay.pendingFadeIn = false
                crossfade(key)
            }
            measurements.record(MeasurementEvent(phase: .overlayRequested, windowCount: 1,
                                                   apiCallDuration: started.duration(to: .now)))
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
        // Removal aborts any in-flight crossfade: the panel and both effect views are torn down,
        // and no animation completion callback exists that could act on a stale overlay.
        guard let overlay = overlays.removeValue(forKey: key) else { return }
        let started = ContinuousClock.now
        overlay.panel.orderOut(nil)
        overlay.panel.close()
        measurements.record(MeasurementEvent(phase: .overlayRemoved, windowCount: 1,
                                               apiCallDuration: started.duration(to: .now)))
    }

    private func effectView(_ material: NSVisualEffectView.Material, size: CGSize) -> NSVisualEffectView {
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.autoresizingMask = [.width, .height]
        effect.material = material
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.isEmphasized = false
        return effect
    }

    /// Crossfade the tier view in on top of the anchor view, which is never faded itself.
    /// The honest option of the two: no frame is composited with an empty panel, and the
    /// anchor tier is declared at least as strong as the target, so intermediate frames are
    /// never less blurred than the start. A focus change, geometry change or removal reaches
    /// `remove(_:)`, which tears the panel down instead of leaving a partial fade.
    private func crossfade(_ key: WindowKey) {
        guard let overlay = overlays[key] else { return }
        overlay.tier = tier
        overlay.tierEffect.material = tier.material
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            // Final state directly, never through alphaValue 0. Reduce Transparency still
            // refuses the material path in reconcile; this only matters if that policy changes.
            overlay.tierEffect.alphaValue = 1
            return
        }
        overlay.tierEffect.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MaterialTier.transitionDuration
            overlay.tierEffect.animator().alphaValue = 1
        }
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
