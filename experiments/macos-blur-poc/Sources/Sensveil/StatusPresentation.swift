import Foundation

public struct StatusPresentation: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let symbol: String

    public init(_ status: ProtectionStatus) {
        switch status {
        case .notRunning:
            title = "未运行"; detail = "应用启动后检查窗口状态"; symbol = "app.dashed"
        case .foreground:
            title = "前台使用中"; detail = "当前应用保持清晰"; symbol = "eye"
        case .protected:
            title = "已保护"; detail = "窗口模糊已确认"; symbol = "checkmark.shield"
        case .cannotProtect(let reason):
            title = "无法保护"; detail = Self.failureDetail(reason); symbol = "exclamationmark.shield"
        case .partialFailure(let reasons):
            title = "部分窗口无法保护"
            detail = Array(Set(reasons.map(Self.failureDetail))).sorted().joined(separator: "；")
            symbol = "exclamationmark.shield"
        case .paused:
            title = "已暂停"; detail = "暂停期间不保护窗口"; symbol = "pause.circle"
        case .disabled:
            title = "未开启"; detail = "单应用保护未开启"; symbol = "power"
        case .outsideSchedule:
            title = "非保护时段"; detail = "当前不在配置的保护时段内"; symbol = "clock.badge.exclamationmark"
        case .noVisibleWindows:
            title = "无可见窗口"; detail = "应用运行中没有可保护的可见窗口"; symbol = "rectangle.on.rectangle.slash"
        }
    }

    private static func failureDetail(_ reason: String) -> String {
        let value = reason.lowercased()
        if value.contains("unverified") || value.contains("blur evidence") {
            return "模糊效果尚未验证，无法确认窗口内容已受保护"
        }
        if value.contains("permission") || value.contains("accessibility") { return "辅助功能权限未授予或窗口信息无法读取" }
        if value.contains("transparency") { return "系统已开启降低透明度，无法可靠模糊" }
        if value.contains("order") || value.contains("layer") { return "窗口相对层级无法确认" }
        if value.contains("ambiguous") || value.contains("match") { return "窗口身份无法唯一确认" }
        if value.contains("eligible") || value.contains("helper") { return "此应用类型不支持保护" }
        if value.contains("sheet") || value.contains("unsupported") || value.contains("nonstandard") { return "部分窗口类型尚未验证" }
        if value.contains("process") { return "应用进程状态无法确认" }
        if value.contains("display") { return "窗口所在显示器无法确认" }
        if value.contains("foreground") { return "前台应用状态无法确认" }
        return "窗口信息或模糊效果无法确认"
    }
}

public enum SensveilMenuAction: Sendable {
    case openManagement, togglePause, quit
}
