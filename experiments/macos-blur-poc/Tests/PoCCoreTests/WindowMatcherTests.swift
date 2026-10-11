import Foundation
import CoreGraphics
import XCTest
@testable import PoCCore

final class WindowMatcherTests: XCTestCase {
    private let process = ProcessInstance(pid: 42, generation: 1)
    private let bounds = CGRect(x: 100, y: 200, width: 500, height: 300)

    func testUniquePublicWindowMapping() {
        let ax = AXWindowCandidate(token: 0, process: process, bounds: bounds, isMinimized: false)
        let key = WindowKey(process: process, cgWindowID: 10)
        let cg = [
            WindowCandidate(key: key, bounds: CGRect(x: 100.5, y: 200.5, width: 500, height: 300), isOnScreen: true, layer: 0),
            window(id: 11, process: ProcessInstance(pid: 43, generation: 1)),
            window(id: 12, process: ProcessInstance(pid: 42, generation: 2)),
            window(id: 13, layer: 1)
        ]
        XCTAssertEqual(WindowMatcher.match(ax: ax, cg: cg), .unique(key))
        XCTAssertEqual(WindowMatcher.matchAll(ax: [ax], cg: cg), [0: .unique(key)])
    }

    func testRejectsAmbiguousAndDuplicateMapping() {
        let first = AXWindowCandidate(token: 0, process: process, bounds: bounds, isMinimized: false)
        let second = AXWindowCandidate(token: 1, process: process, bounds: bounds, isMinimized: false)
        XCTAssertEqual(WindowMatcher.match(ax: first, cg: [window(id: 10), window(id: 11)]), .ambiguous)
        XCTAssertEqual(WindowMatcher.matchAll(ax: [first, second], cg: [window(id: 10)]), [0: .ambiguous, 1: .ambiguous])
    }

    func testRejectsInvalidAndMissingWindows() {
        let ax = AXWindowCandidate(token: 0, process: process, bounds: bounds, isMinimized: false)
        let invalidRects = [CGRect.zero, CGRect.null, CGRect.infinite,
                            CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1),
                            CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0, width: CGFloat.greatestFiniteMagnitude, height: 100),
                            CGRect(x: 0, y: 0, width: -1, height: 1)]
        for rect in invalidRects {
            XCTAssertEqual(WindowMatcher.match(ax: AXWindowCandidate(token: 0, process: process, bounds: rect, isMinimized: false), cg: [window(id: 10)]), .missing)
            XCTAssertEqual(WindowMatcher.match(ax: ax, cg: [WindowCandidate(key: WindowKey(process: process, cgWindowID: 10), bounds: rect, isOnScreen: true, layer: 0)]), .missing)
        }
        XCTAssertEqual(WindowMatcher.match(ax: AXWindowCandidate(token: 0, process: process, bounds: bounds, isMinimized: true), cg: [window(id: 10)]), .missing)
        XCTAssertEqual(WindowMatcher.match(ax: ax, cg: [window(id: 10, onScreen: false)]), .missing)
        XCTAssertEqual(WindowMatcher.match(ax: ax, cg: []), .missing)
    }

    func testMatchesEdgesRatherThanOriginAndSize() {
        let ax = AXWindowCandidate(token: 0, process: process, bounds: bounds, isMinimized: false)
        let candidate = WindowCandidate(key: WindowKey(process: process, cgWindowID: 10), bounds: CGRect(x: 101, y: 200, width: 501, height: 300), isOnScreen: true, layer: 0)
        XCTAssertEqual(WindowMatcher.match(ax: ax, cg: [candidate]), .missing)
        XCTAssertEqual(WindowMatcher.match(ax: ax, cg: [candidate], tolerance: 2), .unique(candidate.key))
        for tolerance in [CGFloat(-1), CGFloat.nan, CGFloat.infinity] {
            XCTAssertEqual(WindowMatcher.match(ax: ax, cg: [window(id: 10)], tolerance: tolerance), .missing)
        }
    }

    func testDuplicateEnumerationTokensAreRejected() {
        let first = AXWindowCandidate(token: 0, process: process, bounds: bounds, isMinimized: false)
        let second = AXWindowCandidate(token: 0, process: process, bounds: CGRect(x: 800, y: 200, width: 500, height: 300), isMinimized: false)
        XCTAssertEqual(WindowMatcher.matchAll(ax: [first, second], cg: [window(id: 10)]), [0: .ambiguous])
    }

    private func window(id: UInt32, process: ProcessInstance? = nil, onScreen: Bool = true, layer: Int = 0) -> WindowCandidate {
        WindowCandidate(key: WindowKey(process: process ?? self.process, cgWindowID: id), bounds: bounds, isOnScreen: onScreen, layer: layer)
    }
}
