import Foundation
import CoreGraphics

public enum WindowMatcher {
    /// Use matchAll for snapshots so cross-window duplicate ownership is checked.
    public static func match(ax: AXWindowCandidate, cg: [WindowCandidate], tolerance: CGFloat = 1) -> WindowMatch {
        result(for: candidateKeys(ax: ax, cg: cg, tolerance: tolerance))
    }

    public static func matchAll(ax: [AXWindowCandidate], cg: [WindowCandidate], tolerance: CGFloat = 1) -> [Int: WindowMatch] {
        let candidates = ax.map { candidateKeys(ax: $0, cg: cg, tolerance: tolerance) }
        var tokens: [Int: Int] = [:]
        var owners: [WindowKey: Set<Int>] = [:]
        for (index, window) in ax.enumerated() {
            tokens[window.token, default: 0] += 1
            for key in candidates[index] {
                owners[key, default: []].insert(index)
            }
        }

        var matches: [Int: WindowMatch] = [:]
        for (index, window) in ax.enumerated() {
            let hasSharedCandidate = candidates[index].contains { (owners[$0]?.count ?? 0) > 1 }
            if tokens[window.token, default: 0] > 1 || hasSharedCandidate {
                matches[window.token] = .ambiguous
            } else {
                matches[window.token] = result(for: candidates[index])
            }
        }
        return matches
    }

    private static func result(for keys: [WindowKey]) -> WindowMatch {
        switch keys.count {
        case 0: .missing
        case 1: .unique(keys[0])
        default: .ambiguous
        }
    }

    private static func candidateKeys(ax: AXWindowCandidate, cg: [WindowCandidate], tolerance: CGFloat) -> [WindowKey] {
        guard !ax.isMinimized, ax.bounds.isValidWindowRect, tolerance.isFinite, tolerance >= 0 else { return [] }
        return cg.filter { candidate in
            candidate.key.process == ax.process && candidate.isEligible &&
                abs(candidate.bounds.minX - ax.bounds.minX) <= tolerance &&
                abs(candidate.bounds.maxX - ax.bounds.maxX) <= tolerance &&
                abs(candidate.bounds.minY - ax.bounds.minY) <= tolerance &&
                abs(candidate.bounds.maxY - ax.bounds.maxY) <= tolerance
        }.map(\.key)
    }
}
