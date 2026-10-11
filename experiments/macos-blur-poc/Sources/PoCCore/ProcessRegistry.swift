import Foundation

/// Shared by main-actor adapters. Identity exists only for this registry's lifetime.
public final class ProcessRegistry {
    private var instances: [Int32: (launchDate: Date, instance: ProcessInstance)] = [:]
    private var nextGeneration: UInt64 = 0

    public init() {}

    public func observe(pid: Int32, launchDate: Date) -> ProcessInstance {
        if let existing = instances[pid], existing.launchDate == launchDate { return existing.instance }
        nextGeneration += 1
        let instance = ProcessInstance(pid: pid, generation: nextGeneration)
        instances[pid] = (launchDate, instance)
        return instance
    }

    public func remove(pid: Int32) { instances.removeValue(forKey: pid) }
}
