import AppKit
import PoCCore
import QuartzCore

@MainActor
final class OverlayMaterialContent: RoundedMaterialEffect {
    let safetyEffect = NSVisualEffectView()
    let tierEffect = NSVisualEffectView()
    let guardLabel = NSTextField(labelWithString: "Sensveil 守护中")
    private(set) var settings = OverlaySettings.defaults
    private(set) var protectionStatus = ProtectionStatus.cannotProtect("Material is unverified")
    private(set) var isProtectionTransitionRunning = false
    private var transitionTicket: UUID?
    private var transitionCompletion: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        state = .active
        blendingMode = .behindWindow
        isEmphasized = false
        wantsLayer = true
        safetyEffect.material = .underWindowBackground
        safetyEffect.state = .active
        safetyEffect.blendingMode = .behindWindow
        safetyEffect.isEmphasized = false
        safetyEffect.autoresizingMask = [.width, .height]
        safetyEffect.wantsLayer = true
        safetyEffect.isHidden = true
        tierEffect.state = .active
        tierEffect.blendingMode = .behindWindow
        tierEffect.isEmphasized = false
        tierEffect.autoresizingMask = [.width, .height]
        tierEffect.wantsLayer = true
        guardLabel.font = .systemFont(ofSize: 14, weight: .medium)
        guardLabel.textColor = .labelColor
        guardLabel.alignment = .center
        guardLabel.isSelectable = false
        guardLabel.isEditable = false
        guardLabel.lineBreakMode = .byClipping
        addSubview(safetyEffect)
        addSubview(tierEffect)
        addSubview(guardLabel)
        apply(settings: .defaults, protectionStatus: .cannotProtect("Material is unverified"))
    }
    required init?(coder: NSCoder) { nil }
    func apply(settings: OverlaySettings, protectionStatus: ProtectionStatus) {
        if self.settings.blurLevel != settings.blurLevel || self.settings.protectionTransition != settings.protectionTransition {
            cancelProtectionTransition()
        }
        self.settings = settings
        self.protectionStatus = protectionStatus
        // Keep the experimentally observed popover anchor in place while switching tiers.
        switch settings.blurLevel {
        case .standard: tierEffect.material = .hudWindow
        case .enhanced: tierEffect.material = .popover
        case .strongest: tierEffect.material = .underWindowBackground
        }
        layout()
    }

    func beginProtectionTransition(reduceMotion: Bool) {
        cancelProtectionTransition()
        guard !reduceMotion, let duration = settings.protectionTransition.duration else { return }

        let ticket = UUID()
        transitionTicket = ticket
        isProtectionTransitionRunning = true
        // The accepted strongest combination covers the selected tier throughout entry.
        safetyEffect.isHidden = false
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = Float(0)
        animation.toValue = Float(1)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        tierEffect.layer?.add(animation, forKey: "protectionEntry")
        transitionCompletion = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(duration))
            } catch {
                return
            }
            guard let self, self.transitionTicket == ticket else { return }
            self.cancelProtectionTransition()
        }
    }

    func cancelProtectionTransition() {
        transitionTicket = nil
        transitionCompletion?.cancel()
        transitionCompletion = nil
        isProtectionTransitionRunning = false
        tierEffect.layer?.removeAnimation(forKey: "protectionEntry")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tierEffect.layer?.opacity = 1
        CATransaction.commit()
        safetyEffect.isHidden = true
    }

    override func layout() {
        super.layout()
        safetyEffect.frame = bounds
        tierEffect.frame = bounds
        let size = guardLabel.fittingSize
        let target = bounds.insetBy(dx: RoundedOverlayGeometry.padding, dy: RoundedOverlayGeometry.padding)
        let fits = size.width + 16 <= target.width && size.height + 16 <= target.height
        guardLabel.isHidden = !settings.showsProtectionLabel || protectionStatus != .protected || !fits
        guardLabel.frame = CGRect(x: bounds.midX - size.width / 2,
                                  y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
