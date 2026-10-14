import AppKit
import QuartzCore
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
        case .enhanced: .popover
        case .strongest: .underWindowBackground
        }
    }

    var summary: String { "\(rawValue) = .\(materialName)" }

    private var materialName: String {
        switch self {
        case .standard: "hudWindow"
        case .enhanced: "popover"
        case .strongest: "underWindowBackground"
        }
    }

    /// Keep the physical popover anchor unchanged when selected tier names are reordered.
    /// Its presence does not certify intermediate-frame protection during the crossfade.
    static let transitionAnchor: MaterialTier = .enhanced

    /// Fixed experiment duration. Not a user setting, not a product blur delay.
    static let transitionDuration: TimeInterval = 0.2
}

@MainActor
private final class MaterialPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class RoundedMaterialEffect: NSVisualEffectView {
    private let shapeMask = CAShapeLayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.mask = shapeMask
        updateMask()
    }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); updateMask() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateMask() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); updateMask() }
    private func updateMask() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeMask.frame = bounds
        shapeMask.contentsScale = window?.backingScaleFactor ?? 1
        shapeMask.path = RoundedOverlayGeometry.maskPath(in: CGRect(origin: .zero, size: bounds.size))
        CATransaction.commit()
    }
}

@MainActor
final class MaterialOverlayCoordinator {
    /// Two stacked effect views. The anchor stays at alpha 1 while the selected tier view
    /// crossfades in on top. Composited blur during the transition remains unverified.
    private final class Overlay {
        let panel: MaterialPanel
        let targetBounds: CGRect
        let protectionBounds: CGRect
        let anchorEffect: NSVisualEffectView
        let tierEffect: NSVisualEffectView
        var tier: MaterialTier
        /// A new panel is composited at the anchor tier with the tier view empty, so it needs
        /// exactly one fade-in after it is ordered on screen.
        var pendingFadeIn = true

        init(panel: MaterialPanel, targetBounds: CGRect, protectionBounds: CGRect, anchorEffect: NSVisualEffectView,
             tierEffect: NSVisualEffectView, tier: MaterialTier) {
            self.panel = panel
            self.targetBounds = targetBounds
            self.protectionBounds = protectionBounds
            self.anchorEffect = anchorEffect
            self.tierEffect = tierEffect
            self.tier = tier
        }
    }

    private var overlays: [WindowKey: Overlay] = [:]
    private var orderingFailures: [WindowKey: String] = [:]
    private var orderingFailureDiagnostics: [WindowKey: String] = [:]
    private var postOrderDiagnostic: String?
    private var naturalCheckDiagnostic: String?
    private let measurements: MeasurementRecorder

    private(set) var tier: MaterialTier = .standard

    var overlayKeys: Set<WindowKey> { Set(overlays.keys) }

    var orderingDiagnosticSummary: String {
        let retainedFailures = orderingFailureDiagnostics.keys.sorted { $0.cgWindowID < $1.cgWindowID }
            .compactMap { orderingFailureDiagnostics[$0] }.joined(separator: "\n")
        let snapshots = [postOrderDiagnostic, naturalCheckDiagnostic,
                         retainedFailures.isEmpty ? nil : "Latched rejected pairs:\n\(retainedFailures)"]
            .compactMap { $0 }
        return snapshots.isEmpty ? "No ordering metadata snapshot" : snapshots.joined(separator: "\n\n")
    }

    /// Exact parameters of the prepared experiment, for operator display and docs.
    var parameterSummary: String {
        let anchor = MaterialTier.transitionAnchor
        return "tier \(tier.summary) · anchor \(anchor.summary) · panel borderless+nonactivating, level .normal, "
            + "ignoresMouseEvents, order(.above, relativeTo: target) · both views state .active, "
            + "blendingMode .behindWindow, isEmphasized false · rounded radius 20pt, padding 8pt per edge"
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

    /// Operator-selected candidate. Existing overlays retain the anchor while re-crossfading.
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
        // Keep a rejected pair failed until its attempt ends, including foreground removal.
        orderingFailures = orderingFailures.filter { attempts.contains($0.key) }
        orderingFailureDiagnostics = orderingFailureDiagnostics.filter { attempts.contains($0.key) }
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
        if !overlays.isEmpty {
            guard let failures = relativeOrderingFailures() else {
                let reason = "Public window order metadata is unavailable; relative layering is unverified"
                for key in attempts {
                    orderingFailures[key] = reason
                    observations[key] = .failed(reason: reason)
                }
                removePanels()
                return observations
            }
            orderingFailures.merge(failures) { previous, _ in previous }
        }

        var createdPanel = false
        for key in attempts {
            if let failure = orderingFailures[key] {
                remove(key)
                observations[key] = .failed(reason: failure)
                continue
            }
            guard let window = windows.first(where: { $0.key == key }), window.isOnScreen,
                  window.layer == 0, valid(window.bounds), key.cgWindowID > 0,
                  valid(screenLayout.primaryScreenFrame),
                  let geometry = RoundedOverlayGeometry(targetBounds: window.bounds) else {
                remove(key)
                observations[key] = .failed(reason: "Validated window geometry or public identity is unavailable")
                continue
            }
            let rect = CoordinateTransform.appKitRect(from: geometry.protectionBounds,
                                                       primaryScreenFrame: screenLayout.primaryScreenFrame)
            let targetRect = CoordinateTransform.appKitRect(from: window.bounds, primaryScreenFrame: screenLayout.primaryScreenFrame)
            guard screenLayout.screenFrames.contains(where: { valid($0) && $0.intersects(targetRect) }) else {
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
                // The anchor view stays at alpha 1 from the first visible frame;
                // the tier view starts empty *on top of it* and is crossfaded in. The panel
                // itself is never faded from alphaValue 0.
                tierView.alphaValue = 0
                anchor.addSubview(tierView)
                panel.contentView = anchor
                overlays[key] = Overlay(panel: panel, targetBounds: window.bounds, protectionBounds: geometry.protectionBounds,
                                        anchorEffect: anchor, tierEffect: tierView, tier: tier)
                createdPanel = true
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
        if createdPanel {
            // One immediate metadata sample per new panel batch; never a protection verdict.
            naturalCheckDiagnostic = nil
            _ = relativeOrderingFailures(postOrder: true)
        }
        return observations
    }

    func removeAll(clearOrderingDiagnostics: Bool = false) {
        removePanels()
        orderingFailures.removeAll()
        orderingFailureDiagnostics.removeAll()
        if clearOrderingDiagnostics {
            postOrderDiagnostic = nil
            naturalCheckDiagnostic = nil
        }
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
        let effect = RoundedMaterialEffect(frame: NSRect(origin: .zero, size: size))
        effect.autoresizingMask = [.width, .height]
        effect.material = material
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.isEmphasized = false
        return effect
    }

    /// Crossfade the tier view in on top of the persistent popover anchor.
    /// Intermediate-frame protection still requires visual acceptance.
    /// A focus change, geometry change or removal reaches
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

    private func relativeOrderingFailures(postOrder: Bool = false) -> [WindowKey: String]? {
        let stage = postOrder ? "Post-order batch" : "Next natural check"
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                  kCGNullWindowID) as? [[String: Any]] else {
            storeOrderingDiagnostic("\(stage): metadataUnavailable", postOrder: postOrder)
            return nil
        }
        let metadata = list.compactMap { item -> OrderedWindowMetadata? in
            guard let id = (item[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { return nil }
            let bounds = (item[kCGWindowBounds as String] as? [String: Any]).flatMap {
                CGRect(dictionaryRepresentation: $0 as CFDictionary)
            }
            return OrderedWindowMetadata(windowID: id, bounds: bounds)
        }
        let orderedIDs = metadata.map(\.windowID)
        let ownIDs = Set(overlays.values.map { UInt32($0.panel.windowNumber) })
        let selectedIDs = ownIDs.union(overlays.keys.map(\.cgWindowID))
        var allMetadata: [UInt32: [String: Any]]?
        if !ownIDs.isSubset(of: Set(orderedIDs)),
           let all = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                               kCGNullWindowID) as? [[String: Any]] {
            // Retain only the selected pairs, never window titles or owner names in the summary.
            allMetadata = [:]
            for item in all {
                if let id = (item[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                   selectedIDs.contains(id) { allMetadata?[id] = item }
            }
        }
        var failures: [WindowKey: String] = [:]
        var rows: [(UInt32, String)] = []
        var classifications: [String: Int] = [:]
        for (key, overlay) in overlays {
            let panelNumber = overlay.panel.windowNumber
            let panelID = UInt32(panelNumber)
            let panelIndex = orderedIDs.firstIndex(of: panelID)
            let targetIndex = orderedIDs.firstIndex(of: key.cgWindowID)
            let result = RelativeWindowOrdering.evaluate(panelID: panelID, targetID: key.cgWindowID,
                protectionBounds: overlay.protectionBounds, windows: metadata, ownOverlayIDs: ownIDs)
            let classification = result.classification.rawValue
            classifications[classification, default: 0] += 1
            if let failure = result.classification.failureReason { failures[key] = failure }
            if rows.count < 20 {
                let panelItem = panelIndex.flatMap { index -> [String: Any]? in
                    list.first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == orderedIDs[index] }
                }
                let targetItem = targetIndex.flatMap { index -> [String: Any]? in
                    list.first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == orderedIDs[index] }
                }
                var row = "\(classification): panel.windowNumber \(panelNumber), target CGID \(key.cgWindowID), isVisible \(overlay.panel.isVisible)"
                row += "\n  onScreen indices panel \(panelIndex.map(String.init) ?? "missing") / target \(targetIndex.map(String.init) ?? "missing")"
                row += "\n  panel CG \(metadataSummary(panelItem, expectedBounds: overlay.protectionBounds))"
                row += "\n  target CG \(metadataSummary(targetItem, expectedBounds: overlay.targetBounds))"
                row += "\n  expected CG bounds \(boundsSummary(overlay.targetBounds))"
                row += "\n  expanded coverage CG bounds \(boundsSummary(overlay.protectionBounds))"
                for intervening in result.interveningWindows.prefix(20) {
                    let bounds = intervening.metadata.bounds.map(boundsSummary) ?? "unavailable"
                    let intersection: String
                    switch intervening.intersection {
                    case .empty: intersection = "none"
                    case .unknown: intersection = "unknown"
                    case .overlap(let rect): intersection = boundsSummary(rect)
                    }
                    row += "\n  between CGID \(intervening.metadata.windowID), bounds \(bounds), intersection \(intersection)"
                }
                if result.interveningWindows.count > 20 {
                    row += "\n  \(result.interveningWindows.count - 20) intervening detail rows omitted"
                }
                if panelIndex == nil {
                    if let allMetadata {
                        let item = allMetadata[panelID]
                        row += "\n  optionAll panel \(item == nil ? "noMatchingCGID" : "presentNotOnScreen"), \(metadataSummary(item, expectedBounds: overlay.protectionBounds))"
                        row += "\n  optionAll target \(metadataSummary(allMetadata[key.cgWindowID], expectedBounds: overlay.targetBounds))"
                    } else {
                        row += "\n  optionAll metadataUnavailable"
                    }
                }
                if !postOrder, result.classification != .ok {
                    orderingFailureDiagnostics[key] = row
                }
                rows.append((key.cgWindowID, row))
            }
        }
        let counts = classifications.keys.sorted().map { "\($0) \(classifications[$0]!)" }.joined(separator: ", ")
        let omitted = overlays.count > rows.count ? "; \(overlays.count - rows.count) detail rows omitted" : ""
        let summary = "\(stage): \(overlays.count) pairs checked; \(counts)\(omitted)\n"
            + rows.sorted { $0.0 < $1.0 }.map(\.1).joined(separator: "\n")
        storeOrderingDiagnostic(summary, postOrder: postOrder)
        return failures
    }

    private func storeOrderingDiagnostic(_ summary: String, postOrder: Bool) {
        if postOrder { postOrderDiagnostic = summary }
        else { naturalCheckDiagnostic = summary }
    }

    private func metadataSummary(_ item: [String: Any]?, expectedBounds: CGRect) -> String {
        guard let item else { return "missing" }
        let layer = (item[kCGWindowLayer as String] as? NSNumber).map { String($0.intValue) } ?? "unknown"
        guard let value = item[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: value as CFDictionary) else {
            return "layer \(layer), bounds unavailable"
        }
        return "layer \(layer), bounds \(boundsSummary(bounds)), matchesExpected \(bounds == expectedBounds)"
    }

    private func boundsSummary(_ bounds: CGRect) -> String {
        "[\(bounds.origin.x), \(bounds.origin.y), \(bounds.width), \(bounds.height)]"
    }

    private func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0 &&
            [rect.minX, rect.maxX, rect.minY, rect.maxY, rect.width, rect.height].allSatisfy(\.isFinite)
    }
}
