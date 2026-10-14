# Sensveil 防窥效果与保护时段 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 macOS 产品中实现统一圆角外扩覆盖、三档模糊、可关闭的守护文案、安全的整体过渡，以及每周多时段和离线中国大陆节假日/调休规则。

**Architecture:** 沿用 SwiftPM 工程、版本化 Codable 配置、SensveilController 保存后生效流程、WindowProtectionCoordinator 应用级焦点和既有 overlay 协议。新增纯函数时段判定和只读内置节假日日历；协调器持有唯一边界定时器。视觉能力先实测放行，再扩展现有模糊实现，不创建通用插件引擎或并存的旧配置入口。

**Tech Stack:** Swift 6、SwiftUI、AppKit、Foundation Calendar/Date、CoreGraphics、XCTest；最低构建目标 macOS 14，无第三方运行时依赖。ScreenCaptureKit + Core Image 仅为满足既有门槛后的条件路线。

**Spec:** [TASK.md](../../../TASK.md)；[PRD](../../product/PRD.md) §4.2/4.3 与 AC-01/05；[实验门槛](../../engineering/POC_RESULTS.md)；[可行性验证](../../engineering/FEASIBILITY_SPIKE.md)。本计划不是通过证据。

## Global Constraints

2026-10-14 最新过渡裁决：保留四档与动画代码，隐藏产品设置入口，实际进入/退出固定200ms；原schema3值保留兼容但不控制当前运行。以下四档步骤作为历史实现记录，体验反馈未通过，不能按已验收宣传。

- 一期只考虑 macOS；Windows 暂缓。
- 全局设置：模糊档位、文案显示、保护时段；圆角为固定行为。2026-10-14 用户批准统一 20pt 圆弧、每边外扩 8pt 完整包围目标矩形，接受外围小范围模糊，不再要求真实轮廓匹配，不新增圆角设置项。
- 模糊档位为“标准、增强、最强”，默认标准；文案默认显示，可关闭；全天保护默认开启。
- 指定时段首次预置周一至周五 09:00–18:00，周末为空；切换模式不重置已保存数据。
- 节假日跟随默认关闭；节假日/调休休息时段默认空，调休上班时段默认 09:00–18:00。
- 多区间、跨午夜、开始含/结束不含；相同起止拒绝保存；跨日区间归属开始日，节假日不能截断前日区间。
- 本机时区，不自动使用北京时间。日历按开始日所属年份查找，未知年份退回每周规则并独立提示，不复用旧年安排。
- 日历只随应用版本内置更新，安装升级并重启后生效；无热更新、后台联网、节日日期猜测或云端配置。
- 整体过渡全局四档200ms/500ms/800ms/关闭，默认200ms（2026-10-14 用户更新）；不能从暴露可读内容的透明状态开始，较长视觉动画不延长最低安全模糊预算。系统“减少动态效果”优先；保存新档位立即取消旧动画。
- 真实保护证据成立才可显示“已保护”或“Sensveil 守护中”；请求提交、回调成功、panel 存在和绘制完成均不是隐私强度证据。
- 失焦至达到最低安全模糊的 PRD 预算仍为 p95 ≤150ms、最大 ≤300ms。200ms 是视觉过渡时间，不得额外延迟安全模糊建立或用户输入。
- 失败显示无法保护，不用实色替代；不使用私有 CGS/AX API、全局置顶、猜测 helper 身份或强行激活目标。
- 保存失败不发布新配置；损坏/未知 schema 保留原文件并锁定修改；不保存原始像素、窗口标题或设备/许可秘密。
- 本地产品迭代使用现有安装脚本安装并运行 `/Applications/Sensveil.app`；fixture 不安装到 Applications。默认 ad-hoc；证书必须显式授权指定；系统拒绝执行则停止，不改 Gatekeeper、不清除隔离、不自动重置 TCC。
- 本次不实现收费、试用、激活、登录启动、自动更新、Windows 或按应用独立时段。

## 当前起点与阻断项

2026-10-13 性能热修复：已修复启动时大图标 TIFF/PNG 处理、同步应用目录刷新与重复界面通知造成的严重卡顿；119 个测试通过，release 产品已安装并运行于 `/Applications/Sensveil.app`，修复后本机采样未再出现原图标热点。证据、负载差异及剩余限制见 [PERFORMANCE_VALIDATION](../../engineering/PERFORMANCE_VALIDATION.md)。Task 8 仍未开始：材料 Gate 为 UNMEASURED，3 人可读性评估尚无评估者，性能修复不代替视觉门槛放行。

| 位置 | 观察到的行为 | 开发影响 |
| --- | --- | --- |
| `ProtectionConfiguration.swift:58–90` | schema 1，只含应用及全局暂停 | 需要兼容迁移到 schema 2 |
| `SensveilController.swift:73–119` | 保存成功后才发布配置 | 沿用，不将 UI 草稿直接送进运行时 |
| `WindowProtectionCoordinator.swift:80–87` | 每次配置变化先撤全部层 | 文案/档位更新需改为差分，避免主动制造保护空档 |
| `WindowProtectionCoordinator.swift:219–231` | 请求提交仍无法保护；关闭条目落到未运行 | 新增未开启/非保护时段；不得靠新增 protected 分支伪造证据 |
| `MaterialOverlayCoordinator.swift:23–42` | 固定 hudWindow 材质，无轮廓、档位或动画 | 三档模糊和真实轮廓必须先做可行性实验 |
| `ManagementView.swift:86–87` | 关闭应用被 UI 强制映射为暂停 | 删除该覆盖，状态统一来自协调器 |
| `Package.swift:16`、`build-apps.sh:25–39` | 无产品资源声明，脚本只拷贝图标 | 节假日资源须同时在 swift test 和安装 app 可读 |
| `POC_RESULTS.md:74–90` | 材料 Gate 为 UNMEASURED | 不能跳过层级/输入验证直接开发捕获路径 |

最高风险：扩大覆盖范围后的完整包含、外缘材料强度和相对层级仍需验证；现有材质无公开模糊半径控制；从透明度 0 淡入违反最低安全模糊要求。2026-10-14 用户已批准统一圆角外扩，见 [ADR-002](../../architecture/ADR-002-expanded-rounded-overlay.md)。其余需求不变，不能擅自改成两档、文字动画或实色层。时段模块可完成，但不是整个需求交付完成。

## 文件边界与依赖

现有源代码基目录：`experiments/macos-blur-poc/Sources/Sensveil/`；测试目录：`experiments/macos-blur-poc/Tests/SensveilTests/`。

新增文件限于明确职责：
- `ProtectionSchedule.swift`：时段模型、校验、归一化、按本地 Calendar 求当前判定和下一状态边界。
- `MainlandHolidayCalendar.swift`：内置 JSON 解码、年份完整性与日期类型查询。
- `Sources/Sensveil/Resources/mainland-holidays.json`：实际官方年度安排，包含来源与版本。
- `ProtectionSettingsView.swift`：设置草稿、时段编辑器、保存/取消，嵌入管理页。
- `ProtectionScheduleTests.swift`、`MainlandHolidayCalendarTests.swift`：行为边界测试；其余沿用现有测试文件。
- 仅条件捕获路线通过门槛时新增 `WindowBlurRenderer.swift`；不预先创建空引擎、协议或捕获壳。

执行顺序：任务 1 固化边界；任务 2 做视觉技术门槛；任务 3–6 做配置/日历/判定/运行时；任务 7 设置 UI；任务 8 集成放行后的视觉路径；任务 9 最终实测。

可并行的真实切片：任务 2 与任务 3–5。协调器、控制器、管理页由单一集成所有者修改；共享文件任务不能同时写。视觉 Gate 未通过不阻止纯时段功能，但阻止任务 8 和整体验收。每个实现任务由集成所有者统一运行相关测试与实际 smoke；并行 worker 不运行测试/构建/格式化，最后统一跑完整套件。

## Task 1: 同步需求基线与固定判定规则

**Files:** Modify `TASK.md`、`docs/product/PRD.md`、`docs/decisions/OPEN_QUESTIONS.md`；核对 `docs/architecture/ADR-001-native-macos.md`，只有选定技术路线改变时更新 ADR。

**Interfaces:** 定义时段资格，不改变 PoCCore reducer 的焦点语义。新增公式：

```text
可启用 = 用户已选择 && 单应用开启 && 位于当前授权额度 && 全局未暂停 && 当前保护时段有效
可保护 = 可启用 && 所需权限有效 && 窗口/完整覆盖受支持 && 模糊引擎正常
需要模糊 = 可保护 && 目标应用不为前台 && 目标窗口当前可见
```

- [ ] 将 TASK 纳入本轮实现基线：三档模糊从旧 PRD 的后续 P2 提升到本轮范围；新增非保护时段、节假日警告与设置入口，不声称能力已实现。
- [ ] 固定状态表：保留额度违规的撤层约束；展示优先级为超额 → 单应用未开启 → 全局暂停/生命周期挂起 → 未运行 → 非保护时段 → 前台使用 → 实际窗口结果。非保护时段不读取模糊能力错误来冒充无法保护；日历警告独立展示。
- [ ] 固定 DST 语义为本机墙钟分钟判断：春季跳过的分钟无实际时刻，不补足时长；秋季重复分钟两次都按同一时段判断。跨日终点按下一自然日处理，不加固定 86400 秒。零长度拒绝；结束 24:00 表示下一日 00:00，不允许开始 24:00。
- [ ] 保留 7 天全部为空的合法配置，界面明确“指定时段为空，当前不会保护”；避免用户误以为保存失败。
- [ ] 将默认值和特殊语义标为本计划采用的实现规则；如用户改变这些规则，先修改需求与相应测试，不将新语义藏在代码里。
- [ ] 对照 TASK 的 14 个 AC 与本计划最后的覆盖表；提交仅本任务文件：`docs: define protection schedule and rendering boundaries`。

## Task 2: 完整覆盖、三档模糊和安全过渡 Gate

**Files:** Modify `Sources/Sensveil/MaterialOverlayCoordinator.swift`、`Sources/Sensveil/WindowTracker.swift`、`Sources/SensveilFixture/main.swift`、`docs/engineering/POC_RESULTS.md`、`docs/engineering/FEASIBILITY_SPIKE.md`（均以实验基目录为准；文档位于仓库 docs）。必要时条件新增 `Sources/Sensveil/WindowBlurRenderer.swift`，只有 Gate 批准后。

**Interfaces:** 后续集成契约仍使用现有 `OverlayCoordinating`，新增方法见任务 8。实验结果必须明确选定的公开 API、支持的窗口类型、每个档位的真实参数、证据有效条件、失败原因，不写无法运行的“配置参数占位”。

- [ ] 使用合成 fixture 和当前产品签名二进制重做 F-03 层级、F-04 一次点击/输入、F-05 材料强度。现有 UNMEASURED 不能当失败或通过。
- [ ] 按 2026-10-14 新需求，验证统一圆角外扩路径在普通圆角、直角、自绘、极小窗和屏幕边缘完整包含目标矩形；增加 1/2/3 倍及小数坐标的光栅覆盖检查。sheet、全屏的身份、层级和交互仍需独立验证。真实轮廓探针保留为历史研究，不再阻断统一圆角几何实施；不使用私有 API 或从标题推断类型。
- [ ] 针对现有材料实验三档候选，逐档进行 12/24/48pt 合成内容可读性观察；材质外观差异不是 blur 差异，三档均需达到 PRD AC-05。
- [ ] 若层级/输入通过而材料隐私强度失败，记录证据后进入已批准的 SCK 条件实验；若只是不能调三档但材料强度通过，先在 ADR/决策清单评审是否允许切换路径，不自行扩大屏幕采集用途。
- [ ] 条件 SCK 实验使用按窗口过滤 + Core Image 模糊，只展示处理后的帧；复用唯一窗口身份、忽略 overlay 自身、缓存 CIContext 而非每帧创建、限制在飞帧和缓存生命周期，不保存像素。拒绝/撤销录屏权限明确失败，不把诊断授权视为自动批准内容采集。
- [ ] 测试整体动画从安全模糊起点过渡至所选档位，而非 `alphaValue = 0` 淡入。如果视觉上无法做到真正整体过渡又满足安全基线，记录不成立并请产品裁决，不改成仅文案动画。
- [ ] 记录失焦到安全模糊的时间与视觉过渡完成时间为两个指标；聚焦撤层期间不能阻挡键盘/鼠标；快速焦点反转与几何变化必须取消过期动画。
- [ ] Gate 输出 PASS/FAIL/UNMEASURED 和支持矩阵；不能产生可信、可失效的保护证据则不开放“已保护”和守护文案。无设备/评估者的组合保持未测。完成后提交：`docs: record protection rendering feasibility gates`，包含实际实验改动。

## Task 3: 设置模型、迁移与保存事务

**Files:** Modify `ProtectionConfiguration.swift`、`SensveilController.swift`；Create `ProtectionSchedule.swift`（模型部分）；Modify `ProtectionConfigurationTests.swift`；相关开发说明随实现更新。

**Interfaces:** `ProtectionConfiguration` 升到 schema 2，新增 `blurLevel: BlurLevel`、`showsProtectionLabel: Bool`、`schedule: ProtectionSchedule`。统一圆角覆盖和固定动画不存开关。

后续2026-10-14用户要求过渡四档：配置继续升级schema3，新增 `protectionTransition`（200/500/800ms/off），schema1/2默认200ms；保留既有迁移和失败事务。圆角仍无独立开关，过渡设置已成为当前需求。

```swift
public enum BlurLevel: String, Codable, CaseIterable, Sendable {
    case standard, enhanced, strongest
}
public enum ProtectionScheduleMode: String, Codable, Sendable {
    case allDay, specified
}
public struct ProtectionTimeRange: Codable, Equatable, Sendable {
    public var startMinute: Int  // 0...1439
    public var endMinute: Int    // 结束相对开始日的分钟偏移，1...2879；必须 > startMinute
}

// 编辑器 HH:mm 结束早于开始时加 1440；归一化后的结束仍保存相对日偏移。
// 例如同日起始区间合并为 00:00–次日12:00，endMinute = 2160，不回绕丢尾段。
public struct ProtectionSchedule: Codable, Equatable, Sendable {
    public var mode: ProtectionScheduleMode
    public var weeklyRanges: [[ProtectionTimeRange]] // 7 项，周一索引 0
    public var followsMainlandHolidays: Bool
    public var holidayRanges: [ProtectionTimeRange]
    public var makeupWorkdayRanges: [ProtectionTimeRange]
    public static let defaultConfiguration: ProtectionSchedule
    public func normalized() throws -> ProtectionSchedule
}
// SensveilController：保存成功后发布并通知现有协调器
public func saveProtectionSettings(
    blurLevel: BlurLevel,
    showsProtectionLabel: Bool,
    schedule: ProtectionSchedule
) throws
```

- [ ] 默认模型预存工作日 09:00–18:00、周末空、节假日空、补班 09:00–18:00，但 mode 为 allDay；因此无需增加“首次初始化”标记，模式来回切换不重置。
- [ ] 在现有 XCTest 增加迁移和无效输入行为测试：schema 1 应用/排序/暂停完整保留；schema 2 非法分钟、周数组长度、零长度区间或未知枚举返回错误；未知版本和写失败原文件不变。只缺旧版新增字段可默认，不能把损坏的 schema 2 当旧配置吞掉。
- [ ] 用现有编码、原子替换、损坏备份模式实现迁移；读取迁移值不马上覆盖旧文件，下一次用户有效保存才写 schema 2。
- [ ] `saveProtectionSettings` 先校验归一化再保存，成功后赋值和更新协调器；失败继续使用原配置，界面展示错误。不顺手重写应用目录或许可模型。
- [ ] 最小 smoke 使用临时文件保存两款应用 + 暂停 + 自定义跨夜时段，重新创建 store 读取并比较实际值；未知 schema 测试字节保持不变。清理临时目录。

测试代码方向（断言消费者可见状态，不测 JSON 排版）：

```swift
let original = Data(#"{"schemaVersion":1,"applications":[],"isGloballyPaused":true}"#.utf8)
let migrated = try JSONDecoder().decode(ProtectionConfiguration.self, from: original)
XCTAssertTrue(migrated.isGloballyPaused)
var edited = migrated
edited.showsProtectionLabel = false
let decoded = try JSONDecoder().decode(
    ProtectionConfiguration.self, from: JSONEncoder().encode(edited))
XCTAssertFalse(decoded.showsProtectionLabel)
XCTAssertTrue(decoded.isGloballyPaused)
```

Run: `swift test --package-path experiments/macos-blur-poc --filter ProtectionConfigurationTests`。先增加测试观察失败，再实现并通过。提交：`feat: persist global protection settings and migrate configuration`。

## Task 4: 官方年度日历与安装资源闭环

**Files:** Create `MainlandHolidayCalendar.swift`、`Sources/Sensveil/Resources/mainland-holidays.json`、`MainlandHolidayCalendarTests.swift`；Modify `Package.swift:16`、`scripts/build-apps.sh:25–39`、实验 README。

**Interfaces:** 本地查询与警告，不改变 `ProtectionStatus` 为日历错误。

```swift
public enum HolidayDayKind: String, Codable, Sendable {
    case rest, makeupWorkday
}
public struct MainlandHolidayCalendar: Sendable {
    public struct YearData: Codable, Sendable {
        public let year: Int
        public let version: String
        public let sourceURLs: [URL]
        public let days: [String: HolidayDayKind] // ISO yyyy-MM-dd；仅例外日期
    }
    public let years: [Int: YearData]
    public static func loadBundled() throws -> MainlandHolidayCalendar
    public init(data: Data) throws
    public func kind(on date: Date, calendar: Calendar) -> HolidayDayKind?
    public func hasYear(_ year: Int) -> Bool
}
```

- [ ] 实施时从国务院/中国政府网官方年度通知取证，录入当前已公布年度，若下一年度尚未公布则不造数据、不猜日期。所有通知中的休息日及补班日完整录入；注明资料日期、版本和官方 URL。
- [ ] 加入校验：同日不能既 rest 又 makeupWorkday、日期必须真实且属对应年份、年份不能重复、缺来源或版本拒绝加载。仅有零散例外日期不能冒充完整年度；只有完成整份官方年度通知核对才发布该年数据。
- [ ] 用 `.process("Resources")` 注册 Sensveil target 资源；检查 SwiftPM 实际生成的 resource_bundle_accessor，构建脚本从实际 binary_path 取对应 `.bundle` 并拷贝到产品 `Contents/Resources` 后再签名。源码加载器在 app 下按该固定 bundle 名从 `Bundle.main.resourceURL` 加载，在 swift test 下用 `Bundle.module`；两处指向同一构建资源，不能复制 JSON 到第二个源路径或回退当前目录/开发机绝对路径。安装 smoke 必须在找不到原构建目录的环境验证，避免开发目录偶然可读掩盖打包缺失。
- [ ] 测试用隔离的合成年度 JSON 验证周末补班、周内放假、缺年、重复日期、非法日期；不把生产节假日表复制成断言。生产年度完整性由官方通知逐日核对记录。
- [ ] 对真实 `.app` 启动后观察界面显示覆盖年份、版本和当前日期类型，确保安装产物不是只有图标。加载失败创建空日历并产生独立警告，周规则继续运行；配置不被修改。
- [ ] 更新数据随应用版本发布，升级后退出旧进程并启动新版本；不加入下载器、更新包或热加载接口。

Run: `swift test --package-path experiments/macos-blur-poc --filter MainlandHolidayCalendarTests`；打包资源 smoke 与下一次集中产品构建合并，不由并行 worker 重复安装。提交：`feat: bundle offline mainland holiday calendar`。

## Task 5: 每周/节假日时段的确定性判定

**Files:** Modify `ProtectionSchedule.swift`；Create `ProtectionScheduleTests.swift`。

**Interfaces:** 用 Date + 注入 Calendar + 注入日历数据；不依赖全局 Date.now 或 UI，当前日和前一日均参与跨午夜匹配。

```swift
public struct ProtectionScheduleEvaluation: Equatable, Sendable {
    public let isActive: Bool
    public let nextTransition: Date?
    public let nextEvaluation: Date // 下一个区间端点/午夜/时区偏移转换中的最早者
    public let missingHolidayYears: Set<Int>
    public let activeSource: String? // 展示每周/节假日/调休规则，不含隐私内容
}
public func evaluateProtectionSchedule(
    _ schedule: ProtectionSchedule,
    at date: Date,
    calendar: Calendar,
    holidays: MainlandHolidayCalendar
) -> ProtectionScheduleEvaluation
```

- [ ] 先写精确边界测试：09:00 含、18:00 不含；周末为空；周一夜间延至周二；周日跨周；节假日空不截断前日；补班覆盖周末；当前/前日缺年分别告警；跟随关闭及全天模式不产生日历警告。
- [ ] 归一化每个开始日的区间：统一使用相对开始日的 `[startMinute,endMinute)`；编辑器输入跨夜先将 end 加 1440；排序并合并重叠/相邻项，保留最大终点，不回绕到 HH:mm。合并后跨度可能大于 24 小时（如 00:00–14:00 与 13:00–次日12:00 合为 36 小时），模型支持并在编辑器显示“次日”。跨开始日合并仅用于求有效集合，不改开始日归属。
- [ ] 对当前日及前一日选择规则：跟随且有对应年份 → 例外日期用对应时段，其余用星期；缺年 → 星期并记录该年警告。当前墙钟分钟与两个开始日区间比较。不要用 secondsSinceEpoch % 86400。
- [ ] 以当前日和前一日生成有效区间；用 Calendar 求下一自然日午夜。在该午夜之前收集区间端点及 TimeZone 的偏移转换候选，用端点前后判定求最早实际变化作为 `nextTransition`；同时以最早端点/偏移转换/午夜作为 `nextEvaluation`。即使当前为空、全天或无变化，也在午夜刷新日期/日历警告；不为寻找数月后的首次变化做无界扫描。重复小时分别用 Calendar 的 first/last 匹配生成候选，回拨点本身也必须参与判断。
- [ ] 使用固定 Calendar/时区测试 DST 跳时和回拨（例如 America/Los_Angeles），测试本机非北京时间、本地跨年和相邻多区间的 union，避免依赖测试机器时区。

边界回归样例：

```swift
var schedule = ProtectionSchedule.defaultConfiguration
schedule.mode = .specified
schedule.followsMainlandHolidays = false
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let before = ISO8601DateFormatter().date(from: "2026-10-12T08:59:59Z")!
let start = ISO8601DateFormatter().date(from: "2026-10-12T09:00:00Z")!
let end = ISO8601DateFormatter().date(from: "2026-10-12T18:00:00Z")!
let holidays = try MainlandHolidayCalendar(data: Data("{\"years\":[]}".utf8))
XCTAssertFalse(evaluateProtectionSchedule(schedule, at: before, calendar: calendar, holidays: holidays).isActive)
XCTAssertTrue(evaluateProtectionSchedule(schedule, at: start, calendar: calendar, holidays: holidays).isActive)
XCTAssertFalse(evaluateProtectionSchedule(schedule, at: end, calendar: calendar, holidays: holidays).isActive)
```

Run: `swift test --package-path experiments/macos-blur-poc --filter ProtectionScheduleTests`；再用 throwaway executable 调用同一纯函数输出跨午夜、调休日、缺年和 DST 的具体状态及 nextTransition，核对后删除脚本。提交：`feat: evaluate weekly and holiday protection intervals`。

## Task 6: 无界面运行的边界触发与状态优先级

**Files:** Modify `WindowProtectionCoordinator.swift`、`FocusMonitor.swift`、`StatusModel.swift`、`StatusPresentation.swift`、`SensveilController.swift`、`ManagementView.swift:86–87`；Modify `WindowProtectionCoordinatorTests.swift`。不新增第二个保护状态引擎。

**Interfaces:** 新增 `.disabled`、`.outsideSchedule`、`.noVisibleWindows` 状态；协调器公开只读 `scheduleEvaluation: ProtectionScheduleEvaluation`，日历警告不进入应用失败枚举。内部 init 可注入 `now: () -> Date`、`calendar: () -> Calendar`、`holidays: MainlandHolidayCalendar`，生产便利 init 保留。

- [ ] 时间事件：FocusEvent.Kind 增加 `.timeChanged`；使用系统 clock-change、time-zone-change、calendar-day-change 通知（以当前 SDK 的 Foundation/AppKit 公开符号为准，不造通知名）。原有 wake/space/screens/权限事件继续走同一 reconcile。
- [ ] 协调器每次 reconcile 重新判定，管理唯一一次性 Timer，在 `nextEvaluation` 到来时触发 reconcile，再安排下一次；Timer 加入 main RunLoop common modes，避免菜单/拖动使时段边界长期延迟。stop/sleep 取消，wake、时间变化和配置变化重排。不要依赖 AX 校准或管理窗口打开，也不增加每秒日历轮询。
- [ ] 按任务 1 状态表先处理关闭、暂停、未运行、非时段；非时段撤层并停止不必要的窗口跟踪，仍保留应用启动/焦点监听。进入时段读当前焦点并重新枚举，不重用过期几何。
- [ ] 移除 ManagementView 的关闭→暂停重映射；未开启就是未开启。无可见窗口单独展示；日历缺年警告在全局摘要并存，不遮住实际保护失败。
- [ ] 实现差分配置：删除/关闭/暂停/时段结束撤对应层；文案改变只更新样式；档位改变安全替换，不先 removeAll。无关配置变化不能使成功窗口失去保护。
- [ ] 用现有 FakeProtectionRuntime 测边界跨越引起撤层/恢复、暂停恢复仍按时段、关闭优先、未知焦点不 reuse、PID 世代清理。注入时间推进，测试不 sleep、不改机器时间。
- [ ] 实际产品设置当前分钟前后的小区间、关闭管理窗口等待边界，观察状态和 overlay 行为；再次打开确认警告和状态，暂停再恢复。未放行模糊时必须保持“无法保护”，不能为了 smoke 写假证据。

Run: `swift test --package-path experiments/macos-blur-poc --filter WindowProtectionCoordinatorTests`。提交：`feat: reconcile protection on schedule and system time changes`。

## Task 7: 全局设置与多时段编辑器

**Files:** Create `ProtectionSettingsView.swift`；Modify `ManagementView.swift`、`SensveilController.swift`、`AppDelegate.swift`。复用 SwiftUI，不新建独立应用或浏览器页面。

**Interfaces:** `ProtectionSettingsView(controller: SensveilController)`；本地草稿独立于已保存配置，保存调用任务 3 的 `saveProtectionSettings`；实例身份以配置数据为准，不把行索引当可持久标识。

- [ ] 模糊三档 Picker、守护文案 Toggle、全天/指定模式；展示圆角覆盖实际状态，不提供半径调节；过渡提供200/500/800ms/关闭四档。
- [ ] 指定模式显示周一至周日，每天添加/删除 0～多个区间；开始/结束采用原生时间控件或明确 HH:mm 输入，跨午夜显示“次日”，结束 24:00 可明确选择；不能在控件里用固定任意日期推导本地时间。
- [ ] 加入跟随开关、节假日与补班编辑器；显示当前本机时区、规则来源、是否处于时段及日历年份/版本。跟随关闭保留草稿，全天模式隐藏而不删除时段；警告不弹抢焦点窗口。
- [ ] 保存前显示非法时刻、零长度区间错误；重叠合并后回显归一化结果；空周显式说明。取消丢弃草稿而非已保存配置；写失败保留草稿和旧运行态。
- [ ] 管理窗口使用可滚动内容避免 7 天时段挤掉应用列表/权限入口；键盘焦点、辅助功能标签、浅深色、高对比下可操作。
- [ ] 保持应用添加/删除、免费 2 款额度、权限入口和关闭窗口不退出行为不变；如果 SCK 路径已获批，权限用途从仅诊断改为准确说明并仅经用户按钮申请。
- [ ] 使用实际安装 app 点击每个新控件：保存→关窗→重开→退出重启，比较时段与开关；非法区间不得生效；不新增源文本/文案复制测试或未运行的 UI 快照。

提交：`feat: add global protection settings and weekly interval editor`。

## Task 8: 圆角覆盖/模糊/文案/动画集成

2026-10-14：此前真实轮廓前提未通过，见[复验记录](../../engineering/CONTOUR_ORDERING_VALIDATION.md)。用户随后批准 [ADR-002](../../architecture/ADR-002-expanded-rounded-overlay.md) 的统一圆角外扩方案，允许开始本任务的几何子项；不再以标准标题窗独立轮廓真值作为几何前提。模糊、文案、动画成功状态仍需任务 2 对应 Gate，不以需求调整自动放行。

**Precondition:** 几何子项已获用户单独批准，可在现有产品材料请求上实现，不新增成功状态。其他视觉子项仍需任务 2 对应 Gate 通过，Task 3 的设置已可读写。失败分支必须能在真实产品运行。

后续用户已验收圆角，明确授权继续档位与文案工程：按[接入范围](../../engineering/BLUR_LABEL_INTEGRATION.md)将历史三候选材料组合接入保存后下发，守护文案实现布局及状态门控。隐私成功证据仍缺失，不能把此次工程授权当模糊可读性通过；安全过渡不在本轮新增范围。

本轮工程结果：保存后下发、三档材料组合更新及文案居中/适配/门控已实现，171 项测试通过，产品已安装。下方三档安全原子切换和成功保护文案任务仍不勾完成：实际强度/切档连续性、可信保护证据未通过，生产文案继续隐藏；安全过渡未新增。详细范围与新二进制权限状态见上述接入记录。

后续用户明确验收修正后的模糊档位，允许继续文案；已完成本机验收profile的窗口证据签发/消费与居中文案显示，186项测试、合成真实panel自检16/16及安装通过，见[最新记录](../../engineering/BLUR_LABEL_INTEGRATION.md)。文案子项在限定profile完成，跨环境矩阵和安全动画任务仍未完成；不追溯宣称全Task8放行。

用户随后验收文案并要求过渡：200ms动画工程已接入，192项测试和生产panel自检21/21通过；进入、前台退出、快速反转、减少动态效果与故障取消实现记录见[过渡验证](../../engineering/PROTECTION_TRANSITION_VALIDATION.md)。下方动画工程内容已实现，但中间帧可读性/平滑度/视觉时延仍未验收，因此不勾整项视觉通过。

**Files:** Modify `MaterialOverlayCoordinator.swift`、`WindowProtectionCoordinator.swift`、`WindowTracker.swift`；条件修改 `WindowBlurRenderer.swift`、`PermissionCoordinator.swift`、`ManagementView.swift`；Modify `MaterialOverlayCoordinatorTests.swift` 和 `WindowProtectionCoordinatorTests.swift`。如改公开 PoCCore 类型，先用 LSP references 找所有产品/PoC/test 调用并一并迁移，无 shim。

**Interfaces:** 扩展而非另建现有接口：

```swift
struct OverlaySettings: Equatable {
    let blurLevel: BlurLevel
    let showsProtectionLabel: Bool
}
// OverlayCoordinating / MaterialPanelPresenting 沿用现有身份与清理入口
func setSettings(_ settings: OverlaySettings)
// OverlayObservation 保留 requestSubmitted 和 failed，增加严格证据类型：
struct OverlayProtectionEvidence: Equatable {
    let key: WindowKey
    let bounds: CGRect
    let blurLevel: BlurLevel
    let validationRevision: String
}
// enum OverlayObservation 增加 case protected(OverlayProtectionEvidence)
```

证据 revision 对应任务 2 验证的公开实现与支持组合；具体 OS/覆盖/DPI/层级/权限/生命周期条件在 renderer 内检查，构造入口只允许验证路径调用，不公开工厂“返回 true”。人工确认按钮不能成为生产证据。若任务 2 不能给出该契约的可信实现，本任务的成功保护、三档、文案和动画集成不开始。

- [x] 实装 `RoundedOverlayGeometry` 与统一圆弧 mask；分开目标 bounds 和实际外扩 bounds，以扩张区域检查夹层；移动/缩放/DPI/屏幕变化更新，未知几何 failure。1/2/3 倍及半像素偏移的光栅测试、真实 CG 外扩带冲突已验证；实际合成模糊隐私及跨屏支持仍需任务 2/9 实测。见[外扩验证](../../engineering/EXPANDED_OVERLAY_VALIDATION.md)。
- [ ] 三个真实模糊参数映射复用已测结果；档位替换在新安全效果 ready 后原子切换，旧安全层不能预先清空。任何帧处理失败/权限变化/期限过期进入失败闭环，不能显示 raw frame。
- [ ] 成功 observation 必须匹配 WindowKey/当前 bounds/所选档位和 validationRevision，否则当过期失败；`requestSubmitted` 仍不能产生已保护。混合结果统计 verified success 而不是请求数量；实际成功窗口与失败窗口并存。
- [ ] 每个成功窗口中心加入不可交互文字视图；不激活、不截输入。用实际文字布局尺寸判断能否完整放入，否则隐藏文字而保留模糊；浅/深色和对比度符合可读性。守护文案关闭只刷新 label，不撤模糊。
- [ ] 整体过渡从完整模糊到目标效果，200/500/800ms/关闭可选；保存取消旧动画，聚焦可淡出，暂停/时段结束、权限失败、几何改变和未知焦点立即中止清理；系统减少动态效果直接取最终状态。工程已实现，四档真实中间帧验收仍待补齐。
- [ ] 动画 completion 使用窗口身份/操作世代，迟到回调不得删除新层、重建旧层或显示旧文字；原有非激活、点击穿透、相对层级检查保留。
- [ ] 增加一个快速反转回归及一个过期证据拒绝回归，覆盖 consumer-visible 错误；现有只验证字面文案、英文错误 substring 的测试删除，不重新钉住新措辞。已测试的焦点/未知状态约束保留。
- [ ] 真实 app 验证多窗口中心文案、三档、调整档位不暴露原文、每秒多次焦点切换、移动缩放、无效覆盖几何、前台无层、部分失败、设置保存失败不改变窗口效果。

Run: `swift test --package-path experiments/macos-blur-poc --filter MaterialOverlayCoordinatorTests` 及 `--filter WindowProtectionCoordinatorTests`；真实 GUI smoke 是必要条件，fake panel 单测不能证明模糊。提交：`feat: render verified window contours and safe blur transitions`。

## Task 9: 集成运行、安装升级与完整验收

**Files:** Update `docs/engineering/MVP_VALIDATION.md`、`docs/engineering/POC_RESULTS.md`、`docs/engineering/DEVELOPMENT.md`、`experiments/macos-blur-poc/README.md`、`README.md`；只有确认需求/技术改变时同步 PRD/ADR。不提前写“已通过”。

- [ ] 单一集成所有者运行全套 XCTest、release 构建、plist lint 与严格签名验证；先清理已作废实验/throwaway 脚本，不保留双配置路径或空 fallback。
- [ ] 使用默认安装流程更新并运行产品，只安装产品。系统评估拒绝则停止并记录缺少的合法签名/执行条件，不绕过安全。CI/构建单验用 SENSVEIL_INSTALL=0，但不能将它记为安装通过。
- [ ] 用旧 schema 1 配置升级产品：应用、排序、暂停不丢；新增设置持久化；升级后内置新日历生效；只读/损坏/写失败均保留文件。只使用合成配置，不提交用户配置。
- [ ] 执行 TASK AC-01…14：星期、多区间、跨午夜/跨周/跨年、节假日、调休、缺年、断网、模式保留、无管理窗口边界触发、睡眠唤醒和系统时间/时区通知。时间逻辑以注入时钟脚本证明，不为测试修改用户系统时钟。
- [ ] 真实画面 100 次焦点切换，至少 3 人评估三档可读性；三窗双屏、混合 DPI、直角/圆角、sheet、全屏/Spaces/Stage Manager/锁屏、降低透明度、高对比和减少动态效果。未具备设备/评估者的行标未测，不缩小支持范围冒充全通过。
- [ ] 记录事件→安全模糊 p50/p95/max、事件→动画完成时间、首次新窗曝光；10 可见窗口记录 CPU/内存、静止与动态成本。用现有预算，不自行提高性能或曝光门槛。
- [ ] 权限撤回/恢复、进程退出/PID复用、捕获失败（条件路线）、显示器拔插后无原帧、实色降级或孤立层；实际成功窗口继续保护，失败准确显示，退出完整释放资源。
- [ ] 在最终安装二进制上观察并记录脱敏结果；进行独立代码/隐私评审。修复后重验受影响路径，最终一次全套检查。开发完成与隐私放行分别标记，整套 Gate/AC 未过不能声明全部完成。

```sh
swift test --package-path experiments/macos-blur-poc
bash experiments/macos-blur-poc/scripts/build-apps.sh
plutil -lint experiments/macos-blur-poc/Resources/Sensveil-Info.plist
codesign --verify --strict /Applications/Sensveil.app
```

仅构建验证（不能替代实际安装/GUI）：

```sh
SENSVEIL_INSTALL=0 bash experiments/macos-blur-poc/scripts/build-apps.sh
codesign --verify --strict experiments/macos-blur-poc/.build/apps/Sensveil.app
```

提交仅交付相关文件：`docs: record protection effects and schedule validation`。

## 验收覆盖与完成定义

| TASK 验收 | 实现任务 | 必需证据 |
| --- | --- | --- |
| AC-01 全局设置 | 3、7、8、9 | 配置重载/迁移 + 两应用实际生效 |
| AC-02 完整覆盖 | 2、8、9 | 外扩包含、DPI、直角/圆角、扩大区域冲突与异常闭环 |
| AC-03 三档 | 2、8、9 | 三档真实模糊 + 三人不可辨读评估 |
| AC-04 文案 | 7、8、9 | 每窗口中心、隐藏条件、关闭不撤层 |
| AC-05 动画 | 2、8、9 | 安全起点、时间测量、反转及几何失效 |
| AC-06 全天 | 3、5、6、9 | 默认/模式切换、焦点、窗口生命周期 |
| AC-07 每周 | 3、5、7、9 | 区间边界、归一化、持久化及编辑 |
| AC-08 节假日 | 4、5、7、9 | 官方年度核对 + 放假/补班覆盖 |
| AC-09 数据更新 | 4、5、9 | 年份缺失提示 + 升级重启新数据 |
| AC-10 自动切换 | 5、6、9 | 注入时间测试 + 关管理页实际边界 |
| AC-11 优先级 | 1、5、6、8、9 | 状态转换、独立警告、未知证据拒绝 |
| AC-12 故障 | 3、6、8、9 | 配置/权限/窗口/渲染实际失败恢复 |
| AC-13 跨日跨年 | 5、6、9 | 开始日语义、本地时区、DST/缺年 |
| AC-14 离线保留 | 3、4、7、9 | 离线安装资源、重启/升级不重置 |

完成必须满足：所有设置可用而非 disabled 壳；内置数据在安装产品可读；边界在管理页关闭时仍触发；所有目标窗口使用已验证真实模糊和完整包围覆盖；无未经验证的成功状态；TASK 14 项和 PRD 隐私/延迟门槛都有观察证据。技术能力不成立时输出阻断事实与产品裁决点，不自行改变其余需求。
