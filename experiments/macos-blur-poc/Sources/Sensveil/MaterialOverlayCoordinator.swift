import AppKit
import QuartzCore
import PoCCore

/// Protection observations combine the accepted local material profile and current placement.
enum OverlayObservation: Equatable {
    case requestSubmitted
    case failed(reason: String)
    case protected(OverlayProtectionEvidence)
}

struct OverlayProtectionEvidence: Equatable {
    static let acceptedRevision = "local-material-2026-10-14-v2"
    let key: WindowKey
    let bounds: CGRect
    let blurLevel: BlurLevel
    let validationRevision: String
}

struct OverlaySettings: Equatable {
    let blurLevel: BlurLevel
    let showsProtectionLabel: Bool
    var protectionTransition: ProtectionTransition = .ms200
    static let defaults = OverlaySettings(blurLevel: .standard, showsProtectionLabel: true)
}

@MainActor
protocol MaterialPanelPresenting: AnyObject {
    var windowID: UInt32 { get }
    func submit(frame: CGRect, above targetID: UInt32)
    func remove()
    func fadeOut(completion: @escaping @MainActor () -> Void)
    func setSettings(_ settings: OverlaySettings)
    func setProtectionEvidence(_ evidence: OverlayProtectionEvidence?)
    var presentationFrame: CGRect? { get }
    var backingScale: CGFloat { get }
}

@MainActor
final class MaterialPanel: NSPanel, MaterialPanelPresenting {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    var windowID: UInt32 { UInt32(windowNumber) }
    let materialContent: OverlayMaterialContent
    private var settings = OverlaySettings.defaults
    private var evidence: OverlayProtectionEvidence?
    private var hasSubmitted = false
    private var exitTicket: UUID?
    var presentationFrame: CGRect? {
        isVisible && materialContent.window === self && !materialContent.isProtectionTransitionRunning ? frame : nil
    }
    var backingScale: CGFloat { backingScaleFactor }

    init(frame: CGRect) {
        materialContent = OverlayMaterialContent(frame: CGRect(origin: .zero, size: frame.size))
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
        materialContent.autoresizingMask = [.width, .height]
        contentView = materialContent
    }

    func submit(frame: CGRect, above targetID: UInt32) {
        setFrame(frame, display: false)
        if !hasSubmitted {
            hasSubmitted = true
            materialContent.beginProtectionTransition(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
        order(.above, relativeTo: Int(targetID))
    }

    func remove() {
        exitTicket = nil
        materialContent.cancelProtectionTransition()
        setProtectionEvidence(nil)
        contentView?.layer?.removeAnimation(forKey: "protectionExit")
        orderOut(nil)
        close()
    }

    func fadeOut(completion: @escaping @MainActor () -> Void) {
        materialContent.cancelProtectionTransition()
        setProtectionEvidence(nil)
        guard let duration = settings.protectionTransition.duration,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            remove()
            completion()
            return
        }
        let ticket = UUID()
        exitTicket = ticket
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.exitTicket == ticket else { return }
                self.exitTicket = nil
                completion()
            }
        }
    }

    func setSettings(_ settings: OverlaySettings) {
        if settings.blurLevel != self.settings.blurLevel { evidence = nil }
        self.settings = settings
        updateContent()
    }

    func setProtectionEvidence(_ evidence: OverlayProtectionEvidence?) {
        self.evidence = evidence
        updateContent()
    }

    private func updateContent() {
        let verified = evidence?.blurLevel == settings.blurLevel
            && evidence?.validationRevision == OverlayProtectionEvidence.acceptedRevision
        materialContent.apply(settings: settings, protectionStatus: verified ? .protected : .cannotProtect("Material is unverified"))
    }
}

@MainActor
class RoundedMaterialEffect: NSVisualEffectView {
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
    private struct Overlay {
        let panel: any MaterialPanelPresenting
        let targetBounds: CGRect
        let protectionBounds: CGRect
        var checkedBlurLevel: BlurLevel?
        var lastEvidence: OverlayProtectionEvidence?
    }

    private struct RetiringOverlay {
        let panel: any MaterialPanelPresenting
        let ticket: UUID
        let targetBounds: CGRect
    }

    private var overlays: [WindowKey: Overlay] = [:]
    private var retiringOverlays: [WindowKey: RetiringOverlay] = [:]
    private var orderingFailures: [WindowKey: String] = [:]
    private let makePanel: (CGRect) -> any MaterialPanelPresenting
    private let orderedWindowMetadata: () -> [OrderedWindowMetadata]?
    private let reduceTransparency: () -> Bool
    private let acceptedEnvironment: () -> MaterialAcceptanceEnvironment
    private let reduceMotion: () -> Bool

    var overlayKeys: Set<WindowKey> { Set(overlays.keys) }
    var retiringKeys: Set<WindowKey> { Set(retiringOverlays.keys) }
    private var settings = OverlaySettings.defaults

    func setSettings(_ settings: OverlaySettings) {
        guard settings != self.settings else { return }
        let tierChanged = settings.blurLevel != self.settings.blurLevel
        if settings.protectionTransition != self.settings.protectionTransition { removeRetiringPanels() }
        self.settings = settings
        for key in overlays.keys {
            if tierChanged {
                overlays[key]?.checkedBlurLevel = nil
                overlays[key]?.lastEvidence = nil
                overlays[key]?.panel.setProtectionEvidence(nil)
            }
            overlays[key]?.panel.setSettings(settings)
        }
    }

    init(makePanel: @escaping (CGRect) -> any MaterialPanelPresenting = { MaterialPanel(frame: $0) },
         orderedWindowMetadata: @escaping () -> [OrderedWindowMetadata]? = {
             guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
             return list.compactMap { item in
                 guard let id = (item[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { return nil }
                 let bounds = (item[kCGWindowBounds as String] as? [String: Any]).flatMap {
                     CGRect(dictionaryRepresentation: $0 as CFDictionary)
                 }
                 return OrderedWindowMetadata(windowID: id, bounds: bounds)
             }
         },
         reduceTransparency: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency },
         acceptedEnvironment: @escaping () -> MaterialAcceptanceEnvironment = { .current },
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.makePanel = makePanel
        self.orderedWindowMetadata = orderedWindowMetadata
        self.reduceTransparency = reduceTransparency
        self.acceptedEnvironment = acceptedEnvironment
        self.reduceMotion = reduceMotion
    }

    func reconcile(_ intents: [WindowKey: OverlayIntent], windows: [WindowCandidate],
                   screenLayout: ScreenLayout, foregroundPID: Int32? = nil) -> [WindowKey: OverlayObservation] {
        var observations: [WindowKey: OverlayObservation] = [:]
        let attempts = Set(intents.compactMap { key, intent in intent == .attemptBlur ? key : nil })
        if foregroundPID == nil || reduceTransparency() || reduceMotion() || !acceptedEnvironment().isAccepted
            || intents.values.contains(where: { if case .cannotProtect = $0 { return true }; return false }) {
            removeRetiringPanels()
        }
        for key in retiringOverlays.keys {
            let candidates = windows.filter { $0.key == key }
            if key.process.pid != foregroundPID || candidates.count != 1 || candidates.first?.isOnScreen != true
                || candidates.first?.layer != 0 {
                removeRetiring(key)
            } else if candidates.first?.bounds != retiringOverlays[key]?.targetBounds {
                removeRetiring(key)
            }
        }
        for key in attempts { removeRetiring(key) }
        for key in Set(overlays.keys).subtracting(attempts) {
            let candidates = windows.filter { $0.key == key }
            if intents[key] == .remove, key.process.pid == foregroundPID,
               let overlay = overlays[key], overlay.lastEvidence != nil,
               candidates.count == 1, candidates.first?.bounds == overlay.targetBounds,
               candidates.first?.isOnScreen == true, candidates.first?.layer == 0,
               overlay.panel.presentationFrame != nil,
               acceptedEnvironment().isAccepted, screenLayout.screenFrames.count == 1,
               settings.protectionTransition.duration != nil,
               !reduceMotion(), !reduceTransparency() {
                retire(key)
            } else { remove(key) }
        }
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

        // A new target geometry expires its old placement before comparing CG snapshots.
        for (key, overlay) in overlays {
            let candidates = windows.filter { $0.key == key }
            if candidates.count == 1, let candidate = candidates.first,
               candidate.isOnScreen, candidate.layer == 0,
               RoundedOverlayGeometry(targetBounds: candidate.bounds) != nil,
               candidate.bounds != overlay.targetBounds {
                remove(key)
            }
        }

        // Check all previous placements from one immutable metadata sample before
        // re-ordering or removing panels can conceal an individual failure.
        var checked = Set<WindowKey>()
        var geometryRetry = Set<WindowKey>()
        if !overlays.isEmpty {
            guard let metadata = orderedWindowMetadata() else {
                removePanels()
                let reason = "Public window order metadata is unavailable; relative layering is unverified"
                for key in attempts {
                    orderingFailures[key] = reason
                    observations[key] = .failed(reason: reason)
                }
                return observations
            }
            let ownIDs = Set(overlays.values.map { $0.panel.windowID } + retiringOverlays.values.map { $0.panel.windowID })
            for (key, overlay) in overlays {
                let result = RelativeWindowOrdering.evaluate(panelID: overlay.panel.windowID,
                    targetID: key.cgWindowID, protectionBounds: overlay.protectionBounds,
                    windows: metadata, ownOverlayIDs: ownIDs)
                if let failure = result.classification.failureReason {
                    orderingFailures[key] = failure
                } else if metadata.first(where: { $0.windowID == overlay.panel.windowID })?.bounds == overlay.protectionBounds,
                          metadata.first(where: { $0.windowID == key.cgWindowID })?.bounds == overlay.targetBounds {
                    checked.insert(key)
                } else {
                    geometryRetry.insert(key)
                }
            }
        }

        for key in attempts {
            if geometryRetry.contains(key) {
                remove(key)
                observations[key] = .failed(reason: "Overlay or target geometry is changing; placement must be rechecked")
                continue
            }
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
            let rect = CoordinateTransform.appKitRect(from: geometry.protectionBounds, primaryScreenFrame: screenLayout.primaryScreenFrame)
            let targetRect = CoordinateTransform.appKitRect(from: window.bounds, primaryScreenFrame: screenLayout.primaryScreenFrame)
            guard screenLayout.screenFrames.contains(where: { valid($0) && $0.intersects(targetRect) }) else {
                remove(key)
                observations[key] = .failed(reason: "Target does not intersect a validated display")
                continue
            }
            // Moving/resizing expires the prior placement; never animate across exposed content.
            if overlays[key]?.targetBounds != window.bounds { remove(key) }
            if overlays[key] == nil {
                overlays[key] = Overlay(panel: makePanel(rect), targetBounds: window.bounds, protectionBounds: geometry.protectionBounds, checkedBlurLevel: nil, lastEvidence: nil)
                overlays[key]?.panel.setSettings(settings)
            }
            let priorCheck = overlays[key]?.checkedBlurLevel == settings.blurLevel
            overlays[key]?.panel.submit(frame: rect, above: key.cgWindowID)
            guard let overlay = overlays[key] else { continue }
            let locallyAccepted = acceptedEnvironment().isAccepted
                && overlay.panel.backingScale == 2
                && screenLayout.screenFrames.count == 1
                && screenLayout.screenFrames.contains(where: { valid($0) && $0.contains(rect) && targetRect != $0 })
            guard locallyAccepted else {
                remove(key)
                observations[key] = .failed(reason: "Material has not been accepted for this system, display or window placement")
                continue
            }
            if checked.contains(key), priorCheck, overlay.panel.presentationFrame == rect,
               overlay.targetBounds == window.bounds {
                let evidence = OverlayProtectionEvidence(key: key, bounds: window.bounds,
                    blurLevel: settings.blurLevel, validationRevision: OverlayProtectionEvidence.acceptedRevision)
                overlay.panel.setProtectionEvidence(evidence)
                overlays[key]?.lastEvidence = evidence
                observations[key] = .protected(evidence)
            } else {
                overlay.panel.setProtectionEvidence(nil)
                overlays[key]?.lastEvidence = nil
                overlays[key]?.checkedBlurLevel = settings.blurLevel
                observations[key] = .requestSubmitted
            }
        }
        return observations
    }

    func removeAll() {
        removePanels()
        orderingFailures.removeAll()
    }

    private func removePanels() {
        for key in Array(overlays.keys) { remove(key) }
        removeRetiringPanels()
    }

    private func remove(_ key: WindowKey) {
        overlays.removeValue(forKey: key)?.panel.remove()
    }

    private func retire(_ key: WindowKey) {
        guard let overlay = overlays.removeValue(forKey: key) else { return }
        removeRetiring(key)
        overlay.panel.setProtectionEvidence(nil)
        let ticket = UUID()
        retiringOverlays[key] = RetiringOverlay(panel: overlay.panel, ticket: ticket, targetBounds: overlay.targetBounds)
        overlay.panel.fadeOut { [weak self] in
            guard let self, self.retiringOverlays[key]?.ticket == ticket else { return }
            self.removeRetiring(key)
        }
    }

    private func removeRetiring(_ key: WindowKey) {
        retiringOverlays.removeValue(forKey: key)?.panel.remove()
    }

    private func removeRetiringPanels() {
        for key in Array(retiringOverlays.keys) { removeRetiring(key) }
    }

    private func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0 &&
            [rect.minX, rect.maxX, rect.minY, rect.maxY, rect.width, rect.height].allSatisfy(\.isFinite)
    }
}

@MainActor
protocol OverlayCoordinating: AnyObject {
    var overlayKeys: Set<WindowKey> { get }
    func reconcile(_ intents: [WindowKey: OverlayIntent], windows: [WindowCandidate], screenLayout: ScreenLayout, foregroundPID: Int32?) -> [WindowKey: OverlayObservation]
    func removeAll()
    func setSettings(_ settings: OverlaySettings)
}

extension MaterialOverlayCoordinator: OverlayCoordinating {}
