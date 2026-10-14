import AppKit
import PoCCore

@MainActor
private final class OrderingValidationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Synthetic public-metadata experiment. No pixels, capture permission or protection verdict.
@MainActor
enum OrderingValidation {
    static func run() async -> Int32 {
        guard let screen = NSScreen.screens.first else {
            emit(["experiment": "relative-ordering", "metadataPassed": false, "reason": "displayUnavailable"])
            return 2
        }
        let visible = screen.visibleFrame
        let targetFrame = CGRect(x: visible.minX + 40, y: visible.minY + 40, width: 240, height: 180)
        let outsideFrame = CGRect(x: targetFrame.maxX + 40, y: targetFrame.minY, width: 140, height: 120)
        let overlapFrame = CGRect(x: targetFrame.maxX - 40, y: targetFrame.minY + 30, width: 140, height: 120)
        let marginFrame = CGRect(x: targetFrame.maxX + 4, y: targetFrame.minY + 30, width: 140, height: 120)
        guard let geometry = RoundedOverlayGeometry(targetBounds: targetFrame) else { return 2 }
        let target = makePanel(frame: targetFrame, color: .systemGreen)
        let third = makePanel(frame: outsideFrame, color: .systemOrange)
        let overlay = makePanel(frame: geometry.protectionBounds, color: .systemGray)
        defer {
            for window in [overlay, third, target] {
                window.orderOut(nil)
                window.close()
            }
        }
        target.orderFront(nil)
        third.order(.above, relativeTo: target.windowNumber)
        overlay.order(.above, relativeTo: third.windowNumber)

        let panelID = UInt32(overlay.windowNumber)
        let targetID = UInt32(target.windowNumber)
        let thirdID = UInt32(third.windowNumber)
        let targetCG = CoordinateTransform.appKitRect(from: targetFrame, primaryScreenFrame: screen.frame)
        let protectionCG = CoordinateTransform.appKitRect(from: geometry.protectionBounds, primaryScreenFrame: screen.frame)
        let poses: [(String, CGRect, RelativeWindowOrdering.Classification)] = [
            ("outside", outsideFrame, .ok),
            ("overlap", overlapFrame, .unrelatedBetween),
            ("marginOnly", marginFrame, .unrelatedBetween),
            ("outsideAgain", outsideFrame, .ok)
        ]
        var passed = 0
        for (name, frame, expected) in poses {
            third.setFrame(frame, display: false)
            let expectedThirdCG = CoordinateTransform.appKitRect(from: frame, primaryScreenFrame: screen.frame)
            var sampled: [OrderedWindowMetadata]?
            var sampleCount = 0
            var pairIndices: [Int] = []
            // Allow public CG metadata to propagate, while leaving AppKit's run loop live.
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(100))
                sampleCount += 1
                guard let metadata = snapshot() else { continue }
                sampled = metadata
                guard let panelIndex = metadata.firstIndex(where: { $0.windowID == panelID }),
                      let thirdIndex = metadata.firstIndex(where: { $0.windowID == thirdID }),
                      let targetIndex = metadata.firstIndex(where: { $0.windowID == targetID }),
                      metadata[panelIndex].bounds == protectionCG,
                      metadata[targetIndex].bounds == targetCG,
                      metadata[thirdIndex].bounds == expectedThirdCG,
                      panelIndex < thirdIndex, thirdIndex < targetIndex else { continue }
                pairIndices = [panelIndex, thirdIndex, targetIndex]
                break
            }
            guard let sampled, !pairIndices.isEmpty else {
                emit(["pose": name, "metadataPassed": false, "reason": "requestedOrderOrGeometryNotObserved",
                      "samples": sampleCount, "expectedTargetBounds": rectangle(targetCG),
                      "expectedThirdBounds": rectangle(expectedThirdCG)])
                continue
            }
            let result = RelativeWindowOrdering.evaluate(panelID: panelID, targetID: targetID,
                protectionBounds: protectionCG, windows: sampled, ownOverlayIDs: [panelID])
            let isExpected = result.classification == expected
            if isExpected { passed += 1 }
            let intersections = result.interveningWindows.map { window -> [String: Any] in
                var details: [String: Any] = ["bounds": window.metadata.bounds.map(rectangle) ?? []]
                switch window.intersection {
                case .empty: details["intersection"] = "none"
                case .unknown: details["intersection"] = "unknown"
                case .overlap(let rect): details["intersection"] = rectangle(rect)
                }
                return details
            }
            emit(["pose": name, "metadataPassed": isExpected, "classification": result.classification.rawValue,
                  "samples": sampleCount, "frontToBackIndices": pairIndices,
                  "targetBounds": rectangle(targetCG), "thirdBounds": rectangle(expectedThirdCG),
                  "protectionBounds": rectangle(protectionCG),
                  "interveningCount": result.interveningWindows.count, "interveningGeometry": intersections])
        }
        emit(["experiment": "relative-ordering", "poses": poses.count, "passed": passed,
              "metadataPassed": passed == poses.count, "visualProtectionValidated": false])
        return passed == poses.count ? 0 : 1
    }

    private static func makePanel(frame: CGRect, color: NSColor) -> NSPanel {
        let panel = OrderingValidationPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.hasShadow = false
        panel.backgroundColor = color
        panel.isOpaque = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.animationBehavior = .none
        return panel
    }

    private static func snapshot() -> [OrderedWindowMetadata]? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                  kCGNullWindowID) as? [[String: Any]] else { return nil }
        return list.compactMap { item in
            guard let id = (item[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { return nil }
            let bounds = (item[kCGWindowBounds as String] as? [String: Any]).flatMap {
                CGRect(dictionaryRepresentation: $0 as CFDictionary)
            }
            return OrderedWindowMetadata(windowID: id, bounds: bounds)
        }
    }

    private static func rectangle(_ rect: CGRect) -> [Double] {
        [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)]
    }

    private static func emit(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        print(line)
    }
}
