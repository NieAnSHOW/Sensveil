import Foundation

struct MeasurementEvent {
    enum Phase: String, CaseIterable { case focusReceived, snapshotReady, invalidated, overlayRequested, overlayRemoved }
    let phase: Phase
    let receivedAt: ContinuousClock.Instant
    let windowCount: Int
    let failures: [WindowIssue.Kind]
    /// Synchronous AppKit request cost, never WindowServer presentation latency.
    let apiCallDuration: Duration?

    init(phase: Phase, receivedAt: ContinuousClock.Instant = .now, windowCount: Int = 0,
         failures: [WindowIssue.Kind] = [], apiCallDuration: Duration? = nil) {
        self.phase = phase
        self.receivedAt = receivedAt
        self.windowCount = windowCount
        self.failures = failures
        self.apiCallDuration = apiCallDuration
    }
}

@MainActor
final class MeasurementRecorder {
    struct Entry {
        let sequence: UInt64
        let event: MeasurementEvent
    }

    private(set) var entries: [Entry] = []
    private(set) var phaseCounts: [MeasurementEvent.Phase: Int] = [:]
    private var sequence = UInt64.random(in: 1...(UInt64.max / 2))

    func record(_ event: MeasurementEvent) {
        sequence += 1
        entries.append(Entry(sequence: sequence, event: event))
        if entries.count > 1_000 { entries.removeFirst(entries.count - 1_000) }
        phaseCounts[event.phase, default: 0] += 1
    }
}
