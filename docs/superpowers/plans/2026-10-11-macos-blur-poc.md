# macOS Blur PoC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立可重复运行的 macOS 实验程序，验证 Sensveil 能否通过公开 API 实现应用失焦模糊、聚焦撤层，并交付可复核的可行性结论。

**Architecture:** 使用独立 Swift Package 承载可测试的窗口匹配与状态逻辑、AppKit 实验程序和安全目标 fixture。先验证 NSVisualEffectView 材料与跨进程窗口相对排序；只有材料隐私强度失败且层级与输入门槛通过时，才进入 ScreenCaptureKit 条件实验。系统能力与人工视觉证据分开记录，不以调用成功推断保护成功。

**Tech Stack:** Swift 6、Swift Package Manager、XCTest、AppKit、ApplicationServices、CoreGraphics；条件使用 ScreenCaptureKit 与 Core Image。无第三方运行依赖。

**Spec:** [PRD](../../product/PRD.md)、[TECH_SELECTION](../../architecture/TECH_SELECTION.md)、[FEASIBILITY_SPIKE](../../engineering/FEASIBILITY_SPIKE.md)。这是可行性阶段，不实现额度、试用、激活服务或正式发行工程。

## Global Constraints

- 首期只考虑 macOS；Windows 暂缓。
- “必须保持模糊效果；失败时明确提示无法保护，不接受不透明遮罩降级。”
- “只有收到覆盖层呈现与目标窗口匹配的确认后，才展示‘已保护’；事件已发出或设置已开启不等于保护生效。”
- 使用公开 API；禁止私有 CGS API、私有 AX 窗口 ID 查询和按进程名推测 helper 归属。
- 每个系统实验先在受控 fixture 上验证，再用于仅包含虚构数据的其他应用；没有权限的实验记录“未测（权限阻断）”，不自动更改或重置用户 TCC 权限。
- macOS 14、Apple Silicon 与 Intel 是建议基线；编译和本机运行不能代替其他 OS/架构真机验证。
- 所有操作仅针对显式选择的测试应用；原始像素只在内存，日志不包含窗口标题、屏幕像素或真实设备标识。
- AC-01 目标为连续 100 次切换，稳态 p95 ≤150ms、最大 ≤300ms；必须分别记录事件处理和实际视觉呈现证据。
- AC-05 为约 50cm、正常显示缩放、至少 3 名独立评估者；12/24/48pt 文本及系统设置变化均须记录。没有评估者时标为未测。
- 提交代码前运行适用检查；每个任务由独立评审者检查后再推进。采用用户 AGENTS 已要求的委派执行方式。

## Review Focus

- 同 PID、同尺寸、同位置的两个窗口不得任意映射：Task 1 拒绝歧义，Task 3 在 fixture 重叠窗口中验证。
- 无关应用覆盖目标时不得被模糊层覆盖：Task 4 检查三层交叠和窗口重新排序，失败就阻断路线。
- 失焦窗口收到一次点击后应直接聚焦：Task 4 验证鼠标穿透、键盘输入及无焦点循环。
- 减少透明度或高对比改变材料时不能悄然变为实色保护：Task 4 重测并使状态失效，Task 5 决定候选路线。
- 权限撤回、PID 复用、睡眠与屏幕变化不能留下错误覆盖：Task 1/3 验证身份失效和生命周期清理，Task 5 记录真实系统结果。

---

## File Map

所有实验代码位于 `experiments/macos-blur-poc/`，不提前建立正式 `apps/macos/` 工程。

| 文件 | 单一职责 |
| --- | --- |
| `Package.swift` | macOS 14 deployment target、核心库、两个 executable 和测试目标 |
| `Sources/PoCCore/WindowModel.swift` | 运行实例、公开窗口 ID、几何与权限/保护状态数据类型 |
| `Sources/PoCCore/WindowMatcher.swift` | AX/CG 候选的保守唯一匹配，不读取系统 API |
| `Sources/PoCCore/ProtectionReducer.swift` | 焦点、权限与窗口生命周期输入到覆盖意图的纯逻辑 |
| `Sources/PoCCore/CoordinateTransform.swift` | CG 全局点坐标到 AppKit 全局点坐标转换 |
| `Tests/PoCCoreTests/{WindowMatcherTests,ProtectionReducerTests,CoordinateTransformTests}.swift` | 无 TCC、无真实窗口的确定性断言 |
| `Sources/SensveilPoC/main.swift` | NSApplication 启动与退出 |
| `Sources/SensveilPoC/PoCController.swift` | 显式选择目标、启停实验、订阅状态与资源清理 |
| `Sources/SensveilPoC/DiagnosticWindow.swift` | 非营销式诊断面板：权限、目标 PID、窗口计数、实验状态 |
| `Sources/SensveilPoC/PermissionCoordinator.swift` | AX preflight、显式请求及条件 capture preflight |
| `Sources/SensveilPoC/WindowTracker.swift` | CG 枚举、AX 观察、运行实例归属、低频校准 |
| `Sources/SensveilPoC/FocusMonitor.swift` | 当前前台应用、NSWorkspace 事件与系统生命周期 |
| `Sources/SensveilPoC/MaterialOverlayCoordinator.swift` | 非激活、输入穿透材料层的位置与相对排序 |
| `Sources/SensveilPoC/MeasurementRecorder.swift` | 单调时间、匿名事件序号和阶段耗时；禁止敏感日志 |
| `Sources/SensveilFixture/main.swift` | 专用目标应用、3 个窗口、sheet、虚构文本与内容更新 |
| `Resources/{SensveilPoC,SensveilFixture}-Info.plist` | 稳定 bundle ID 与实验应用元数据 |
| `scripts/build-apps.sh` | 从 release SPM 产物组装两个 `.app`，执行 ad-hoc 签名 |
| `README.md` | 构建、权限、fixture 使用和证据采集步骤 |
| `Sources/SensveilPoC/CaptureBlurExperiment.swift` | 仅通过条件 gate 后创建的 SCK/CI 候选实验 |
| `docs/engineering/POC_RESULTS.md` | 实测环境、支持矩阵、证据、未测项与结论 |

## Task 1: Pin Conservative Identity, Geometry and State Rules

**Files:** Create `experiments/macos-blur-poc/Package.swift`、`Sources/PoCCore/*.swift` 和 `Tests/PoCCoreTests/*.swift`，具体文件见 File Map。

**Interfaces:**

- `ProcessInstance: Hashable, Sendable` 包含 `pid: Int32` 与 `generation: UInt64`；由 tracker 每次发现启动/退出重新枚举时维护实例世代，PID 相同不能复用旧世代。
- `WindowKey: Hashable, Sendable` 包含 `process: ProcessInstance` 与 `cgWindowID: UInt32`；ID 只来自公开 CG 窗口列表。
- `WindowCandidate` 包含 `key: WindowKey`、`bounds: CGRect`、`isOnScreen: Bool`、`layer: Int`；`AXWindowCandidate` 包含本次枚举 `token: Int`、`process: ProcessInstance`、`bounds: CGRect`、`isMinimized: Bool`。不把 AX token 当持久窗口 ID。
- `WindowMatcher.match(ax: AXWindowCandidate, cg: [WindowCandidate], tolerance: CGFloat = 1) -> WindowMatch`；结果为 `.unique(WindowKey)`、`.missing` 或 `.ambiguous`。只使用同运行实例、普通窗口层、有效矩形和各边误差 ≤1pt 的唯一候选。
- `WindowMatcher.matchAll(ax: [AXWindowCandidate], cg: [WindowCandidate], tolerance: CGFloat = 1) -> [Int: WindowMatch]`；输出按 AX token 索引，多个 AX 对应同一 CG ID 时全部标为 ambiguous。tracker 使用此批量入口，不能绕过重复检查。
- `CoordinateTransform.appKitRect(from cgRect: CGRect, primaryScreenFrame: CGRect) -> CGRect`；CG/AX 输入为全局点坐标，AppKit 输出也是点坐标，禁止乘 Retina 倍率。主屏基准必须由当前屏幕布局提供，不能假定所有显示器从零起始。
- `ScreenLayout` 包含菜单栏所在主显示器 `primaryScreenFrame: CGRect` 和当前显示器点矩形 `[CGRect]`；Y 翻转使用主显示器 height，不能按各副屏 height 翻转。
- `PermissionState` 为 `.unknown`、`.notGranted`、`.granted`；AX 的 Bool preflight 不能区分尚未请求与已拒绝，不编造 `.denied`。
- `ProtectionInput` 包含 `frontmost: ProcessInstance?`、`selected: Set<ProcessInstance>`、`windows: [WindowCandidate]`、`previousOverlayKeys: Set<WindowKey>`、`permissions: [PermissionState]`、`isSuspended: Bool` 和 `requiresRevalidation: Bool`；`ProtectionReducer.reduce(_ input: ProtectionInput) -> [WindowKey: OverlayIntent]` 输出 `.remove`、`.attemptBlur` 或 `.cannotProtect(reason: String)`。previousOverlayKeys 中不在当前可覆盖集合的 ID 均 remove，因此退出/PID世代变化可清理旧层。
- `requiresRevalidation` 由屏幕布局/Space/唤醒事件置 true，完成新一批窗口快照与当前权限校验后才置 false；为 true 时先撤旧层，清空旧呈现证据，不能继续显示保护成功。
- reducer 只决定意图；`.attemptBlur` 不产生“已保护”。后续系统 adapter 发布 `.idle`、`.foreground`、`.unavailable(reason:)` 或 `.experimentalOverlayPendingVerification`。

- [ ] **Step 1: 创建 Package manifest。** 使用 `swift-tools-version: 6.0`、`.macOS(.v14)`；此任务先只注册 PoCCore 与 PoCCoreTests，后续任务添加 executable。
- [ ] **Step 2: 编写核心规则的失败测试。** 采用下表断言，不访问 TCC 或运行中的应用。

| 测试名 | 输入与期望 |
| --- | --- |
| `testUniquePublicWindowMapping` | 同实例单候选、四边误差各 0.5pt → unique；其他 PID/世代/layer 候选不参与 |
| `testRejectsAmbiguousAndDuplicateMapping` | 同位置同尺寸两个 CG ID → ambiguous；两个 AX token 同时匹配一个 CG ID → 整组拒绝 |
| `testRejectsInvalidAndMissingWindows` | 空/非有限矩形、AX 最小化、候选不在屏幕 → 不产生覆盖意图 |
| `testAppFocusClearsAllThreeWindows` | 同实例 3 窗口、当前前台相同 → 3 个 remove；另一实例前台 → 3 个 attemptBlur |
| `testPermissionAndSuspensionInvalidateProtection` | 缺 AX/unknown → cannotProtect；全局暂停/目标退出 → remove；不生成 protected |
| `testProcessGenerationInvalidatesOldWindow` | PID 相同、世代从 1 变 2 → 旧 WindowKey remove，不能继承匹配 |
| `testGlobalPointCoordinates` | 主屏 `(0,0,1440,900)`、CG `(100,200,500,300)` → AppKit `(100,400,500,300)` |
| `testNegativeAndMixedDisplayCoordinates` | 同主屏、CG `(-1280,0,1280,1024)` → AppKit `(-1280,-124,1280,1024)`；2x backing scale 不改变点矩形 |

- [ ] **Step 3: 运行 `swift test --package-path experiments/macos-blur-poc`。** 期望因尚无核心接口而失败，保留失败摘要。
- [ ] **Step 4: 实现上述四个核心文件的最小逻辑。** 重复映射拒绝作为整次窗口匹配校验，保留失败原因供诊断，不能用窗口标题打破歧义。
- [ ] **Step 5: 运行同一测试命令。** 期望全部核心测试通过。
- [ ] **Step 6: 请求独立审阅并提交此任务文件。** 审阅重点为歧义拒绝、状态命名、全局坐标；使用 `test: establish macOS PoC identity and state rules`，不包含其他人的改动。

## Task 2: Build Stable Experiment Apps and Safe Fixtures

**Files:** Modify `Package.swift`；Create `Sources/SensveilPoC/{main,PoCController,DiagnosticWindow,PermissionCoordinator}.swift`、`Sources/SensveilFixture/main.swift`、两份 Info.plist、`scripts/build-apps.sh` 与 `README.md`。

**Interfaces:**

- `@MainActor PermissionCoordinator.accessibilityStatus() -> PermissionState` 使用 `AXIsProcessTrusted`；`requestAccessibility()` 仅由用户按钮触发 `AXIsProcessTrustedWithOptions`，随后重新 preflight，不以提示出现判定授予。
- `@MainActor PoCController.selectTarget(bundleIdentifier: String)` 和 `setExperimentEnabled(_ enabled: Bool)`；初始关闭，首个目标为 fixture，拒绝缺 bundle ID、SensveilPoC 自身和不可验证 helper。
- 稳定实验 bundle ID 为 `com.nieanshow.sensveil.poc`；fixture 为 `com.nieanshow.sensveil.fixture`。它们与未来产品身份分开。
- `scripts/build-apps.sh` 从仓库相对位置以 `MACOSX_DEPLOYMENT_TARGET=14.0` 构建并写入被忽略的 `.build/apps/{SensveilPoC,SensveilFixture}.app`；`CFBundleExecutable`、`CFBundleIdentifier`、`LSMinimumSystemVersion=14.0` 正确，实验工具可 `LSUIElement=true`，fixture 为正常前台应用。
- 此脚本执行 ad-hoc codesign；不声称 Developer ID、公证、生产 TCC 身份稳定或跨机器可信。反复编译导致 TCC 变化时记录现象，不自动重置用户权限。

- [ ] **Step 1: 给 Package manifest 添加两个 executable target。** PoC 依赖 PoCCore，fixture 不依赖保护引擎。
- [ ] **Step 2: 实现安全 fixture。** 生成 3 个普通窗口、可打开/关闭的 sheet、移动/缩放/最小化控件；只展示 `测试用户甲 / SAMPLE ACCOUNT`、无效号码 `000-0000-0001`、虚构金额和 12/24/48pt 文本，显式标记 `SYNTHETIC TEST DATA`，另可创建两个完全重叠的同尺寸窗口。
- [ ] **Step 3: 实现 PoC 启动、诊断面板与权限按钮。** 展示目标、权限和“实验尚未验证”；授权拒绝时可继续使用诊断，禁止自动弹循环授权框或显示“已保护”。
- [ ] **Step 4: 编写 app bundle 构建脚本与 plist。** 脚本失败即非零退出，读取当前 Swift binary path，不把本机绝对路径写进仓库。
- [ ] **Step 5: 运行 `bash experiments/macos-blur-poc/scripts/build-apps.sh`。** 期望 release 构建成功、两 app 元数据可由 `plutil -lint` 检查、`codesign --verify --strict` 验证通过；将实际 Swift/Xcode/SDK/CPU 架构记录到 README 的环境示例或结果文件，不能预填成功。
- [ ] **Step 6: 本机打开两个 app 并只操作 fixture。** 期望 fixture 可独立激活、三个窗口/sheet 可操作，PoC 初始关闭；若本机没有完整 SDK，保留可运行的纯逻辑检查，系统实验标记未测并报告工具链缺口。
- [ ] **Step 7: 请求独立审阅并提交此任务文件。** 使用 `feat: add repeatable macOS PoC bundles and safe fixture`。

## Task 3: Observe Public Window Metadata, Focus and Lifecycle

**Files:** Create `Sources/SensveilPoC/{WindowTracker,FocusMonitor,MeasurementRecorder}.swift`、`Sources/PoCCore/ProcessRegistry.swift` 和 `Tests/PoCCoreTests/ProcessRegistryTests.swift`；Modify `PoCController.swift`、`DiagnosticWindow.swift`；Extend `ProtectionReducerTests.swift`。

**Interfaces:**

- `@MainActor FocusMonitor.start(onEvent: @escaping (FocusEvent) -> Void)`、`stop()`；启动先读取 `NSWorkspace.shared.frontmostApplication`，再观察激活/启动/退出通知。`FocusEvent` 包含单调 `receivedAt: ContinuousClock.Instant` 与当前实例，不持久化 PID。
- `@MainActor WindowTracker.snapshot(for target: ProcessInstance) -> WindowSnapshot`、`start(for target: ProcessInstance, onChange: @escaping (WindowSnapshot) -> Void)`、`stop()`；WindowSnapshot 包含唯一映射窗口和 `.missing/.ambiguous/.unsupported` 问题。公开 CG 列表使用 `[.optionOnScreenOnly, .excludeDesktopElements]`，提供 `kCGWindowNumber`、owner PID、bounds、layer、on-screen 信息；AX 负责窗口几何、最小化和通知。
- AX observer callback 进入 MainActor 后同步；保留 observation/run loop source，关闭时释放。通知不支持则每 1 秒校准；激活、屏幕参数变化、Space 变化、唤醒后立即重枚举。不可无限高频 CG 枚举。
- `MeasurementRecorder.record(_ event: MeasurementEvent)` 保存单调阶段时间、随机会话内序号、窗口数量与匿名失败类别；不写窗口标题、图像、原始 PID 或本机路径。
- `ProcessRegistry.observe(pid: Int32, launchDate: Date) -> ProcessInstance` 保持同 PID/启动时间的世代，启动时间变化分配新世代；`remove(pid: Int32)` 使下次观察重新分配。FocusMonitor 与 tracker 共用注册表；缺少可核验启动时间的运行实例不可作为保护目标。

- [ ] **Step 1: 添加运行实例注册表失败测试。** 同 PID/启动时间保持世代；PID 复用启动时间改变、明确退出后重新观察均产生新世代；不同 PID 不冲突。窗口关闭/最小化/退出、布局/恢复与校准的核心 reducer 行为复用 Task 1 的既有证据，仅新增未覆盖断言。
- [ ] **Step 2: 运行核心测试并确认新增注册表测试失败。** 失败必须指向尚未实现的注册表接口，不能是无关构建故障。
- [ ] **Step 3: 实现 ProcessRegistry、FocusMonitor 与 WindowTracker。** 唯一关联从 Task 1 matcher 得到；受支持窗口仅限可证明归属的普通顶层窗口，sheet 可验证后纳入，无法映射的弹窗/helper明确异常。
- [ ] **Step 4: 接入 MeasurementRecorder 与诊断状态。** 诊断显示匹配/拒绝计数和原因，处理任务取消或退出后不再发布旧快照。
- [ ] **Step 5: 运行 `swift test --package-path experiments/macos-blur-poc` 与 app 构建脚本。** 期望逻辑测试与两 executable 均通过。
- [ ] **Step 6: 用 fixture 执行枚举与生命周期检查。** 覆盖三个窗口、重复几何歧义、sheet、创建关闭、最小化、移动缩放、退出重启；期望歧义被拒绝且无人为补 ID，诊断不称保护成功。双屏/睡眠等不可用条件记未测。
- [ ] **Step 7: 请求独立审阅并提交此任务文件。** 使用 `feat: track public macOS windows and focus lifecycle`。

## Task 4: Test Material Blur, Relative Layering and Click-Through

**Files:** Create `Sources/SensveilPoC/MaterialOverlayCoordinator.swift`；Modify `PoCController.swift`、`DiagnosticWindow.swift`、`MeasurementRecorder.swift`；Create initial `docs/engineering/POC_RESULTS.md`。

**Interfaces:**

- `@MainActor MaterialOverlayCoordinator.reconcile(_ intents: [WindowKey: OverlayIntent], windows: [WindowCandidate], screenLayout: ScreenLayout) -> [WindowKey: OverlayObservation]` 和 `removeAll()`。
- `OverlayObservation` 为 `.requestSubmitted` 或 `.failed(reason:)`，记录 API 调用阶段；`NSWindow.isVisible`/`order` 返回均不证明 WindowServer 最终合成画面。
- 每目标创建不激活、无边框、透明背景、`ignoresMouseEvents=true` 的 NSPanel；NSVisualEffectView 使用 `.behindWindow` 与明确材料/state 候选，无覆盖动画。覆盖标题栏与内容，不采用全局浮动级别。
- 用公开 `order(_:relativeTo:)` 与 `cgWindowID` 尝试放在目标之上，保持无关上层窗口仍在其上；若跨进程相对排序不可靠，报告失败并阻断，不改用全局置顶或激活目标作为补偿。
- `.canJoinAllApplications`（macOS 13+）、`.fullScreenAuxiliary` 等仅作为全屏/Stage Manager 的待测候选行为；它们不保证窗口实际可加入或覆盖系统快照。
- 屏幕/材料设置变化或层级失效立即令证据过期；`NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` 后重测/标为未验证。减少透明度生成实色即此材料路径失败。

- [ ] **Step 1: 编写结果记录模板。** 为 F-01 至 F-16、AC-01 至 AC-06 设置“未测”初值，记录环境、复现步骤、事件耗时、呈现证据方法、材料设置、可读性人数和失败范围。
- [ ] **Step 2: 实现 MaterialOverlayCoordinator。** 应用前台时全部撤层，失焦时对唯一匹配可见窗口尝试覆盖；失效/退出清理 panel，不调用 makeKey/orderFrontRegardless。
- [ ] **Step 3: 接入控制器与材料变化监听。** 工具 UI 使用“实验覆盖中（未验证）”或“无法保护：原因”，不把 `.requestSubmitted` 展示为“已保护”。
- [ ] **Step 4: 运行核心测试与 app 构建脚本。** 期望通过，并用本地 SDK header/interface 检查每个使用 API 的 availability；明确记录当前 SDK 与 target 14，不把新 SDK 编译成功写成 macOS 14 运行成功。
- [ ] **Step 5: 执行相对层级与输入实验。** 用 fixture 两个不同 bounds 的部分交叠窗口，加 PoC DiagnosticWindow 作无关应用上层遮挡，形成三层叠放；改变前后顺序、点击后台窗口、输入字符，期望一次点击直接进入原窗口、无焦点循环、无错误覆盖无关窗口。完全重复几何仅验证拒绝，不用作覆盖通过证据。任一失败记录 F-03/F-04 失败。
- [ ] **Step 6: 执行材料与系统设置实验。** 浅色/深色、减少透明度、高对比、动态内容逐一试验；只采集安全 fixture，12/24/48pt 可读性由 3 人独立测试，没有人数则 AC-05 未测。材料仍可读或变实色均不算通过。
- [ ] **Step 7: 更新 POC_RESULTS 的材料 gate。** 层级/输入失败 → 路线待阻断评审；仅材料强度失败且层级/输入通过 → Task 5 允许 SCK 条件实验；材料通过 → 不创建 SCK 文件、不请求录屏权限。
- [ ] **Step 8: 请求独立审阅并提交此任务文件。** 使用 `feat: evaluate material blur and relative window ordering`。

## Task 5: Conditional Capture Experiment and Evidence-Based Decision

**Files:** Modify `docs/engineering/POC_RESULTS.md`、实验 `README.md`；条件 Create `Sources/SensveilPoC/CaptureBlurExperiment.swift`，条件 Modify `PermissionCoordinator.swift`、`PoCController.swift`、`DiagnosticWindow.swift`。只有证据需要调整建议时才修改 `TECH_SELECTION.md` 或新增 ADR，不擅自降低 PRD 要求。

**Interfaces (conditional only):**

- `@MainActor CaptureBlurExperiment.start(windowID: UInt32, onResult: @escaping (CaptureResult) -> Void) async throws`、`stop() async`；使用已唯一验证的公开 window ID 查找 SCWindow，按单窗口过滤。优先 `SCContentFilter(desktopIndependentWindow:)`（12.3+）与 SCStream；`includeChildWindows`（14.2+）必须 availability guard，在14.0上不使用。SCScreenshotManager（14.0+）可独立测量候选，但不照搬需要15+的示例API。
- `CaptureResult` 为 `.awaitingBlurredFrame`、`.blurredFrame` 或 `.failed(reason:)`；firstFrameUnavailable/尚未收到完整帧为等待状态，诊断仍显示未保护。只提供已模糊输出，原始缓冲永不进入呈现视图。CIGaussianBlur 边界 clamp 后 crop 到目标尺寸；输出仍使用 Task 4 已验证的相对层级/input 策略。
- capture preflight 仅在条件 gate 允许后调用，授权请求仅用户主动触发；权限不生效、流中断、无完整帧、渲染异常时立即标为无法保护并撤销无有效内容的层。PoC 不采用未验证的旧帧宽限策略。

- [ ] **Step 1: 复核 Task 4 的材料 gate。** 在 POC_RESULTS 写明 SCK 为“无需执行”“允许执行”或“被基础层级/输入失败阻断”，附对应证据。
- [ ] **Step 2 (conditional): 实现 CaptureBlurExperiment 与显式录屏权限入口。** 按窗口 SCK 流、只渲染完整且已模糊帧，排除覆盖反馈，前台停止不必要捕获，启动首帧等待计入事件/曝光记录。
- [ ] **Step 3 (conditional): 执行捕获失败与权限实验。** 测试拒绝/撤回、无帧、流中断、内容更新、overlay 反馈与退出清理；任何原始帧呈现或实色降级均失败；不可注入的系统条件记未测。
- [ ] **Step 4: 执行可获得的完整 F-01 至 F-16 矩阵。** Safari/TextEdit/Terminal/Electron 仅放虚构测试内容；多屏、不同缩放、Spaces、全屏、Stage Manager、Mission Control、Dock、锁屏唤醒与强制退出逐项记录，无法安全/实际运行者记未测。
- [ ] **Step 5: 记录时延与资源证据。** 100 次切换分别统计 event→reconcile、event→order/remove请求的 p50/p95/max；真实呈现只用独立外部视觉测量/安全fixture帧证据标注采样率与不确定性。没有可靠呈现测量则 AC-01 未测，不把 order 时间称为显示时间。新窗首次曝光另外记录；10 窗口 CPU/驻留内存与静止/动态条件不足时 F-14 未测。
- [ ] **Step 6: 运行核心测试与两 app 的 repeatable build。** 输出实际命令、成功/失败摘要和已用 API availability 检查结果，macOS 14 与 Intel 未运行时仍明确未验证。
- [ ] **Step 7: 形成 POC_RESULTS 结论。** 只在基础模糊、相对层级、输入、权限与实际视觉门槛都有通过证据时建议进入 MVP；不完整为“未具备放行证据”，基础 API 失败为“路线不成立”，局部空间失败为“需要调整范围”。未测不等同失败或通过；附独立评估记录与范围。
- [ ] **Step 8: 请求独立全量评审。** 评审者核对代码/证据/未测项和对外状态文案；有重要问题先修复再复检，通过后提交 `docs: record macOS blur PoC evidence and decision`（如执行 SCK，代码使用单独 `feat:` 提交）。

## Execution Review Gate

本计划完成后的第一步是让用户评审实验范围与执行安排，等待其确认计划；用户 AGENTS 已要求委派，推荐保持 subagent-driven，不重复询问 native/subagent 二选一。确认后以逐任务实施、逐任务独立 review、最后全量 review 的方式推进。

计划 gate 不等于产品可行性放行。只有 Task 5 的证据满足 PRD 门槛才可提出建立正式应用工程；单台当前 Mac 的编译与视觉演示不能代替 macOS 14、Intel、多屏及 3 人可读性评估。缺乏外部条件时交付可重复实验程序和准确未测清单，不编造结论。

## API Evidence

文档能力描述须结合所用 SDK header/interface 检查；当前开发环境核验为 Xcode 26.2 / Swift 6.2.3，不代表最低系统已运行通过。

- [CGWindowListOption](https://developer.apple.com/documentation/coregraphics/cgwindowlistoption)：窗口枚举采用公开 option 组合，不存在 `.onScreenExceptDesktop`。
- [NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview)：提供系统材料，没有跨应用隐私可读性保证。
- [NSWindow order(_:relativeTo:)](https://developer.apple.com/documentation/appkit/nswindow/order(_:relativeto:))：相对排序是实验 API 调用，不能以调用成功推断最终显示。
- [canJoinAllApplications](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications)：macOS13+候选能力，资格与实际系统空间行为仍需测试。
- [SCContentFilter desktopIndependentWindow](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:)) 与 [SCStreamConfiguration](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration)：按实际 API availability 检查14.0路径与14.2新增属性。
- [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement_h)：外部窗口定位与事件；坐标转换依据主显示器基准验证。
