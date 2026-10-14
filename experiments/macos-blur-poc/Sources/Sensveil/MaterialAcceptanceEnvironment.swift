import AppKit
import Darwin

struct MaterialAcceptanceEnvironment: Equatable {
    let version: OperatingSystemVersion
    let build: String
    let architecture: String
    let increasedContrast: Bool

    static var current: Self {
        var count = 0
        sysctlbyname("kern.osversion", nil, &count, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(1, count))
        let result = bytes.withUnsafeMutableBytes { buffer in
            sysctlbyname("kern.osversion", buffer.baseAddress, &count, nil, 0)
        }
        let build = result == 0 ? String(bytes: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? "" : ""
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "unsupported"
        #endif
        return Self(version: ProcessInfo.processInfo.operatingSystemVersion, build: build,
            architecture: architecture, increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
    }

    var isAccepted: Bool {
        version.majorVersion == 27 && version.minorVersion == 0 && version.patchVersion == 1
            && build == "26A434" && architecture == "arm64" && !increasedContrast
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.version.majorVersion == rhs.version.majorVersion && lhs.version.minorVersion == rhs.version.minorVersion
            && lhs.version.patchVersion == rhs.version.patchVersion && lhs.build == rhs.build
            && lhs.architecture == rhs.architecture && lhs.increasedContrast == rhs.increasedContrast
    }
}
