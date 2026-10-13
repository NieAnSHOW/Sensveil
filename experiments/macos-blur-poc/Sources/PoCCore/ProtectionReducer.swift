public enum ProtectionReducer {
    public static func reduce(_ input: ProtectionInput) -> [WindowKey: OverlayIntent] {
        let eligible = input.windows.filter { input.selected.contains($0.key.process) && $0.isEligible }
        var intents = Dictionary(uniqueKeysWithValues: input.previousOverlayKeys.map { ($0, OverlayIntent.remove) })
        let permissionsGranted = !input.permissions.isEmpty && input.permissions.allSatisfy { $0 == .granted }

        let knownPID = input.frontmostPID.flatMap { $0 > 0 ? $0 : nil }
        for window in eligible {
            let isForeground = input.frontmost.map { $0 == window.key.process } ?? (knownPID == window.key.process.pid)
            if input.isSuspended || input.requiresRevalidation || isForeground {
                intents[window.key] = .remove
            } else if input.frontmost == nil && knownPID == nil {
                intents[window.key] = .cannotProtect(reason: "Foreground process is unknown; protection evidence is stale.")
            } else if !permissionsGranted {
                intents[window.key] = .cannotProtect(reason: "Required permission is unavailable or has not been checked.")
            } else {
                intents[window.key] = .attemptBlur
            }
        }
        return intents
    }
}
