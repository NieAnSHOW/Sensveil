import Foundation
import XCTest
@testable import PoCCore

final class ProcessRegistryTests: XCTestCase {
    func testSamePIDAndLaunchDatePreserveInstance() {
        let registry = ProcessRegistry()
        let date = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(registry.observe(pid: 42, launchDate: date), registry.observe(pid: 42, launchDate: date))
    }

    func testReusedPIDGetsNewGeneration() {
        let registry = ProcessRegistry()
        let first = registry.observe(pid: 42, launchDate: Date(timeIntervalSince1970: 100))
        let second = registry.observe(pid: 42, launchDate: Date(timeIntervalSince1970: 101))
        XCTAssertEqual(first.pid, second.pid)
        XCTAssertNotEqual(first.generation, second.generation)
    }

    func testExplicitExitInvalidatesEvenSameLaunchDate() {
        let registry = ProcessRegistry()
        let date = Date(timeIntervalSince1970: 100)
        let first = registry.observe(pid: 42, launchDate: date)
        registry.remove(pid: 42)
        XCTAssertNotEqual(first, registry.observe(pid: 42, launchDate: date))
    }

    func testDifferentPIDsRemainIndependent() {
        let registry = ProcessRegistry()
        let date = Date(timeIntervalSince1970: 100)
        let first = registry.observe(pid: 42, launchDate: date)
        let second = registry.observe(pid: 43, launchDate: date)
        registry.remove(pid: 43)
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first.generation, second.generation)
        XCTAssertEqual(first, registry.observe(pid: 42, launchDate: date))
    }
}
