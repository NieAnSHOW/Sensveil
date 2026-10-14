import Combine
import XCTest
@testable import Sensveil

@MainActor
final class PermissionCoordinatorTests: XCTestCase {
    func testUnchangedPermissionRefreshDoesNotInvalidateObservers() {
        let coordinator = PermissionCoordinator()
        var accessibilityUpdates = 0
        var screenRecordingUpdates = 0
        let accessibilitySubscription = coordinator.$accessibility.dropFirst().sink { _ in accessibilityUpdates += 1 }
        let screenRecordingSubscription = coordinator.$screenRecording.dropFirst().sink { _ in screenRecordingUpdates += 1 }
        defer {
            accessibilitySubscription.cancel()
            screenRecordingSubscription.cancel()
        }

        coordinator.refresh()
        coordinator.refresh()

        XCTAssertEqual(accessibilityUpdates, 0)
        XCTAssertEqual(screenRecordingUpdates, 0)
    }
}
