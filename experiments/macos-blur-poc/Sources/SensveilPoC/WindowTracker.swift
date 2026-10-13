import AppKit
@preconcurrency import ApplicationServices
import PoCCore

struct WindowIssue: Equatable {
    enum Kind: String { case missing, ambiguous, unsupported, accessibilityUnavailable, processUnavailable, metadataUnavailable }
    let kind: Kind
    let reason: String
}

/// A recognised window that is deliberately not protected. Exclusions always fail closed —
/// the window never enters the protected set — but they do not block the rest of the
/// snapshot, so one auxiliary window (menu, tooltip, sheet) cannot void validated windows.
struct WindowExclusion: Equatable {
    enum Kind: String { case sheet, dialog, floating, nonstandardWindow, auxiliaryLayer }
    let kind: Kind
    let reason: String
}

struct WindowSnapshot {
    let target: ProcessInstance
    let receivedAt: ContinuousClock.Instant
    let windows: [WindowCandidate]
    let issues: [WindowIssue]
    let exclusions: [WindowExclusion]
    let minimizedCount: Int
    let cgCount: Int
    let axCount: Int
    let notificationFallback: Bool

    static func unavailable(_ target: ProcessInstance, kind: WindowIssue.Kind, reason: String) -> Self {
        Self(target: target, receivedAt: .now, windows: [], issues: [WindowIssue(kind: kind, reason: reason)],
             exclusions: [], minimizedCount: 0, cgCount: 0, axCount: 0, notificationFallback: true)
    }
}

@MainActor
private final class AXObservationContext {
    weak var tracker: WindowTracker?
    let session: UUID
    init(tracker: WindowTracker, session: UUID) { self.tracker = tracker; self.session = session }
}

@MainActor
final class WindowTracker {
    private let registry: ProcessRegistry
    private var target: ProcessInstance?
    private var onChange: ((WindowSnapshot) -> Void)?
    private var session = UUID()
    private var calibration: Task<Void, Never>?
    private var pendingRefresh: Task<Void, Never>?
    private var observer: AXObserver?
    private var observerContext: UnsafeMutableRawPointer?
    private var notificationFallback = false

    init(registry: ProcessRegistry) { self.registry = registry }

    func start(for target: ProcessInstance, onChange: @escaping (WindowSnapshot) -> Void) {
        stop()
        self.target = target
        self.onChange = onChange
        refresh()
        let activeSession = session
        calibration = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.session == activeSession else { return }
                self.refresh()
            }
        }
    }

    func stop() {
        session = UUID()
        calibration?.cancel(); calibration = nil
        pendingRefresh?.cancel(); pendingRefresh = nil
        releaseObserver()
        target = nil
        onChange = nil
    }

    func refresh() {
        guard let target else { return }
        onChange?(snapshot(for: target))
    }

    fileprivate func notificationReceived(session: UUID) {
        guard self.session == session, pendingRefresh == nil else { return }
        pendingRefresh = Task { @MainActor [weak self] in
            guard let self, self.session == session, !Task.isCancelled else { return }
            self.pendingRefresh = nil
            self.refresh()
        }
    }

    func snapshot(for target: ProcessInstance) -> WindowSnapshot {
        guard let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated,
              let launchDate = app.launchDate,
              registry.observe(pid: target.pid, launchDate: launchDate) == target else {
            releaseObserver()
            return .unavailable(target, kind: .processUnavailable, reason: "Process lifetime cannot be verified")
        }
        guard AXIsProcessTrusted() else {
            releaseObserver()
            return .unavailable(target, kind: .accessibilityUnavailable, reason: "Accessibility permission is unavailable")
        }
        let application = AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        guard let elements = attribute(application, kAXWindowsAttribute) as? [AXUIElement] else {
            releaseObserver()
            return .unavailable(target, kind: .accessibilityUnavailable, reason: "Accessibility windows could not be read")
        }
        guard let metadata = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else {
            releaseObserver()
            return .unavailable(target, kind: .metadataUnavailable, reason: "Public window metadata is unavailable")
        }
        var cg: [WindowCandidate] = []
        var issues: [WindowIssue] = []
        for item in metadata where (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == target.pid {
            guard let number = item[kCGWindowNumber as String] as? NSNumber,
                  let bounds = item[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  let layer = item[kCGWindowLayer as String] as? NSNumber,
                  let visible = item[kCGWindowIsOnscreen as String] as? NSNumber else {
                issues.append(WindowIssue(kind: .metadataUnavailable, reason: "Incomplete public window metadata")); continue
            }
            cg.append(WindowCandidate(key: WindowKey(process: target, cgWindowID: number.uint32Value), bounds: rect,
                                      isOnScreen: visible.boolValue, layer: layer.intValue))
        }
        // Classification runs before matching: only standard top-level AX windows are
        // protection candidates. Sheets, dialogs, floating and other window kinds are
        // recorded as fail-closed exclusions instead of blocking the whole snapshot.
        var ax: [AXWindowCandidate] = []
        var auxiliary: [(kind: WindowExclusion.Kind, reason: String, bounds: CGRect?)] = []
        var exclusions: [WindowExclusion] = []
        var minimizedCount = 0
        for (index, element) in elements.enumerated() {
            let role = attribute(element, kAXRoleAttribute) as? String
            let subrole = attribute(element, kAXSubroleAttribute) as? String
            guard role == kAXWindowRole, subrole == kAXStandardWindowSubrole else {
                let classified = Self.classify(role: role, subrole: subrole)
                auxiliary.append((classified.kind, classified.reason, Self.rect(point(element), size(element))))
                exclusions.append(WindowExclusion(kind: classified.kind, reason: classified.reason))
                continue
            }
            guard let minimized = attribute(element, kAXMinimizedAttribute) as? Bool else {
                issues.append(WindowIssue(kind: .unsupported, reason: "Window minimization state is unavailable")); continue
            }
            if minimized { minimizedCount += 1; continue }
            guard let position = point(element), let elementSize = size(element) else {
                issues.append(WindowIssue(kind: .unsupported, reason: "AX window geometry is unavailable")); continue
            }
            ax.append(AXWindowCandidate(token: index, process: target, bounds: CGRect(origin: position, size: elementSize), isMinimized: false))
            // A sheet is exposed as an AXSheet child of its parent, not as an entry of
            // kAXWindowsAttribute (measured), so its public CG identity is paired here.
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                for child in children where attribute(child, kAXRoleAttribute) as? String == kAXSheetRole {
                    let reason = "Sheet windows are not validated for protection"
                    exclusions.append(WindowExclusion(kind: .sheet, reason: reason))
                    auxiliary.append((.sheet, reason, Self.rect(point(child), size(child))))
                }
            }
        }
        let matches = WindowMatcher.matchAll(ax: ax, cg: cg)
        var accepted: [WindowCandidate] = []
        for element in ax {
            switch matches[element.token] ?? .missing {
            case .unique(let key):
                if let candidate = cg.first(where: { $0.key == key }) { accepted.append(candidate) }
            case .missing: issues.append(WindowIssue(kind: .missing, reason: "AX window has no unique public CG match"))
            case .ambiguous: issues.append(WindowIssue(kind: .ambiguous, reason: "Duplicate geometry or ownership is ambiguous"))
            }
        }
        let acceptedKeys = Set(accepted.map(\.key))
        for candidate in cg where !acceptedKeys.contains(candidate.key) {
            guard candidate.layer == 0 else {
                exclusions.append(WindowExclusion(kind: .auxiliaryLayer,
                                                 reason: "Non-normal CG window layer is excluded (menus, status items, tooltips)"))
                continue
            }
            // A layer-0 CG window explained by a non-standard AX window is already reported as
            // excluded. Only a layer-0 window with no AX identity at all can be unprotectable
            // content the tracker cannot account for, so that case still blocks the snapshot.
            guard !auxiliary.contains(where: { Self.sameGeometry(candidate.bounds, $0.bounds) }) else { continue }
            issues.append(WindowIssue(kind: .unsupported, reason: "Visible layer-0 CG window has no validated AX mapping"))
        }
        var seen = Set<String>()
        let deduplicated = exclusions.filter { seen.insert("\($0.kind.rawValue)|\($0.reason)").inserted }
        if self.target == target { configureObserver(application: application, target: target) }
        return WindowSnapshot(target: target, receivedAt: .now, windows: accepted, issues: issues,
                              exclusions: deduplicated, minimizedCount: minimizedCount, cgCount: cg.count,
                              axCount: elements.count, notificationFallback: notificationFallback)
    }

    private static func classify(role: String?, subrole: String?) -> (kind: WindowExclusion.Kind, reason: String) {
        if role == kAXSheetRole { return (.sheet, "Sheet windows are not validated for protection") }
        switch subrole {
        case kAXDialogSubrole, kAXSystemDialogSubrole:
            return (.dialog, "Dialog windows are not validated for protection")
        case kAXFloatingWindowSubrole, kAXSystemFloatingWindowSubrole:
            return (.floating, "Floating windows are not validated for protection")
        default:
            return (.nonstandardWindow,
                    "Unvalidated AX window kind (role \(role ?? "none") / subrole \(subrole ?? "none"))")
        }
    }

    private static func rect(_ position: CGPoint?, _ size: CGSize?) -> CGRect? {
        guard let position, let size, size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Same 1pt tolerance as `WindowMatcher`, so the exclusion mapping stays consistent with matching.
    private static func sameGeometry(_ lhs: CGRect, _ other: CGRect?) -> Bool {
        guard let other, !lhs.isNull, !other.isNull else { return false }
        return abs(lhs.minX - other.minX) <= 1 && abs(lhs.maxX - other.maxX) <= 1 &&
            abs(lhs.minY - other.minY) <= 1 && abs(lhs.maxY - other.maxY) <= 1
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func point(_ element: AXUIElement) -> CGPoint? {
        guard let raw = attribute(element, kAXPositionAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var value = CGPoint.zero
        return AXValueGetValue(unsafeDowncast(raw, to: AXValue.self), .cgPoint, &value) ? value : nil
    }

    private func size(_ element: AXUIElement) -> CGSize? {
        guard let raw = attribute(element, kAXSizeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var value = CGSize.zero
        return AXValueGetValue(unsafeDowncast(raw, to: AXValue.self), .cgSize, &value) ? value : nil
    }

    private func configureObserver(application: AXUIElement, target: ProcessInstance) {
        if observer != nil { return }
        releaseObserver()
        notificationFallback = false
        var created: AXObserver?
        let result = AXObserverCreate(target.pid, { _, _, _, refcon in
            // This observer source is installed exclusively on the main CFRunLoop.
            guard CFRunLoopGetCurrent() === CFRunLoopGetMain(), let refcon else { return }
            MainActor.assumeIsolated {
                let context = Unmanaged<AXObservationContext>.fromOpaque(refcon).takeUnretainedValue()
                context.tracker?.notificationReceived(session: context.session)
            }
        }, &created)
        guard result == .success, let created else { notificationFallback = true; return }
        observer = created
        observerContext = Unmanaged.passRetained(AXObservationContext(tracker: self, session: session)).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                     kAXUIElementDestroyedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
                     kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
                     kAXSheetCreatedNotification, kAXApplicationHiddenNotification, kAXApplicationShownNotification] {
            addNotification(created, element: application, name: name)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    }

    private func addNotification(_ observer: AXObserver, element: AXUIElement, name: String) {
        let notification = name as CFString
        if AXObserverAddNotification(observer, element, notification, observerContext) != .success {
            notificationFallback = true
        }
    }

    private func releaseObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        // Release the source/observer before refcon; callbacks never use destroyed elements.
        observer = nil
        if let observerContext { Unmanaged<AXObservationContext>.fromOpaque(observerContext).release() }
        observerContext = nil
    }
}
