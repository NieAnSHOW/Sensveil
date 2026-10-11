# macOS Sensveil MVP Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

Goal: 将现有 macOS Blur PoC 收敛为可用的 Sensveil 菜单栏 MVP：用户可选择真实 GUI 应用、保存保护配置，并在目标应用失焦时按已验证窗口尝试模糊，无法可靠保护时明确显示“无法保护”。

Architecture: 保留 experiments/macos-blur-poc 的 Swift 6/SPM 工程，新增 Sensveil executable target。复用 PoCCore 的窗口身份、匹配、焦点和保护 reducer；AppKit 管理菜单栏、非激活模糊 panel 和生命周期，SwiftUI 管理应用列表、权限和状态。应用目录、Codable 配置和保护协调器分离，fixture 只作为测试目标。

Tech Stack: Swift 6、SwiftUI、AppKit、ApplicationServices Accessibility、CoreGraphics、Swift Package Manager、XCTest；无第三方运行时依赖；最低 macOS 14。

Spec: docs/product/PRD.md、docs/architecture/TECH_SELECTION.md、docs/architecture/ADR-001-native-macos.md。本计划不实现支付、试用计时、激活码或服务端。

## Global Constraints

- 首期只支持 macOS；Windows 暂缓。
- 必须使用模糊；失败时显示无法保护，不得降级为不透明遮罩。
- 覆盖请求提交不等于保护成功；只有覆盖层与目标窗口的匹配证据成立后才可显示已保护。
- 只使用公开 API；不得使用私有 CGS/AX API 或按进程名猜测 helper 归属。
- 配置身份使用 bundle identifier；无 bundle ID、Sensveil 自身及其 helper 必须拒绝。
- 免费额度最多 2 个配置条目；第三个条目被阻止，删除后释放额度。
- 配置使用版本化 Codable 文件；不得保存窗口标题、像素、激活码、私钥或原始设备标识。
- 只保留显式 Screen Recording 权限入口；本计划不实现 ScreenCaptureKit、支付、试用或激活服务。
- launch-at-login 入口明确 disabled；不得伪装成可用。
- SensveilFixture 继续作为测试/手工验收目标，不出现在产品选择器。

## Review Focus

- 目录去重并排除自身、helper、无 bundle ID；同 bundle ID 只占一个额度。
- 配置损坏、未知 schema 或写入失败不能静默清空并显示正常保护。
- 同应用内窗口切换不应改变应用级模糊意图。
- 窗口映射部分失败时保留成功窗口，但状态必须是部分异常或无法保护。
- 退出、PID 复用、睡眠/唤醒、Space/显示器变化必须清理旧 panel 并重新验证。

## File Map

- experiments/macos-blur-poc/Package.swift：注册 Sensveil executable 与 SensveilTests。
- Sources/Sensveil/AppDelegate.swift：菜单栏生命周期、管理窗口、退出清理。
- Sources/Sensveil/SensveilController.swift：配置、目录、权限、FocusMonitor/WindowTracker/OverlayCoordinator 协调。
- Sources/Sensveil/ManagementView.swift：应用列表、添加/删除、单应用开关、暂停、权限和状态。
- Sources/Sensveil/ApplicationCatalog.swift：运行中及已安装 GUI 应用发现、搜索、NSOpenPanel 选择。
- Sources/Sensveil/ProtectionConfiguration.swift：版本化 Codable 配置、读写和免费额度。
- Sources/Sensveil/StatusModel.swift：产品状态和失败范围。
- Sources/Sensveil/WindowProtectionCoordinator.swift：多目标状态归并和 overlay 生命周期。
- Sources/Sensveil/{PermissionCoordinator,WindowTracker,FocusMonitor,MaterialOverlayCoordinator}.swift：由 PoC 迁移并去除 fixture-only guard。
- Tests/SensveilTests/*.swift：配置、目录、协调器和状态测试。
- Resources/Sensveil-Info.plist、scripts/build-apps.sh、README.md：产品 bundle、构建和运行说明；fixture 文件保留。

### Task 1: 本地配置与免费额度

Files:
- Create Sources/Sensveil/ProtectionConfiguration.swift and StatusModel.swift.
- Modify Package.swift and SensveilController.swift.
- Test Tests/SensveilTests/ProtectionConfigurationTests.swift.

Interfaces:
- ProtectedApplication: Codable, Equatable, Identifiable，字段 bundleIdentifier、displayName、iconData、isEnabled、sortIndex；id 为 bundleIdentifier。
- ProtectionConfiguration: Codable, Equatable，字段 schemaVersion、applications、isGloballyPaused。
- ConfigurationStore (@MainActor): load() throws, save(_:), add(_:to:) throws, remove(bundleIdentifier:from:)。
- ConfigurationError: freeLimitReached、invalidBundleIdentifier、unsupportedSchema、readFailed、writeFailed。
- ProtectionStatus: notRunning、foreground、protected、partialFailure([String])、cannotProtect(String)、overFreeLimit、paused。

- [ ] Step 1: 写失败测试：默认配置、重复 ID 去重、关闭条目仍占额度、第三项返回 freeLimitReached、删除后可添加、未知 schema 不覆盖原文件。
- [ ] Step 2: 运行 swift test --package-path experiments/macos-blur-poc --filter ProtectionConfigurationTests，确认先失败。
- [ ] Step 3: 实现 Codable 模型和 ConfigurationStore。文件位于 Application Support/Sensveil/config.json，使用临时文件替换；读取损坏文件先保留同目录 corrupt 副本并返回错误。
- [ ] Step 4: 运行配置和 PoCCore 全量测试。
- [ ] Step 5: 独立审阅并提交 feat: add local protection configuration and free limit。

### Task 2: 真实应用目录和选择器

Files:
- Create Sources/Sensveil/ApplicationCatalog.swift.
- Modify ManagementView.swift and SensveilController.swift.
- Test Tests/SensveilTests/ApplicationCatalogTests.swift.

Interfaces:
- ApplicationDescriptor: Identifiable, Equatable，字段 bundleIdentifier、displayName、url、iconData、isRunning。
- ApplicationCatalog (@MainActor): list(search: String = "") -> [ApplicationDescriptor]、chooseApplication() async -> ApplicationDescriptor?、descriptor(for:)。
- list 合并 NSWorkspace.runningApplications 与已安装 .app，按 bundle ID 去重排序；过滤后台-only/helper、自身、fixture、缺 bundle ID 和无法读取 Info.plist 的应用。
- chooseApplication 使用 NSOpenPanel，仅允许 .app；解析失败返回明确错误，不以名称替代 ID。

- [ ] Step 1: 写纯值测试，覆盖过滤、搜索、去重、自排除；使用临时 Info.plist fixture，不启动第三方应用。
- [ ] Step 2: 运行 swift test --package-path experiments/macos-blur-poc --filter ApplicationCatalogTests，确认先失败。
- [ ] Step 3: 实现目录。运行中应用优先，安装目录补齐；图标转 PNG 仅用于缩略图，失败可为空。
- [ ] Step 4: 在 ManagementView 增加搜索、应用信息和“添加应用…”；第三项保留原配置并显示免费额度提示。
- [ ] Step 5: 明确 fixture 只能由手工验收启动，产品目录和控制器不提供固定 fixture 按钮。
- [ ] Step 6: 运行目录、配置和核心测试，独立审阅并提交 feat: add real macOS application picker。

### Task 3: 多目标焦点、窗口和模糊协调

Files:
- Create Sources/Sensveil/WindowProtectionCoordinator.swift.
- Modify Sources/Sensveil/WindowTracker.swift, FocusMonitor.swift, MaterialOverlayCoordinator.swift.
- Modify PoCCore reducer/model only when product status fields require it.
- Test Tests/SensveilTests/WindowProtectionCoordinatorTests.swift.

Interfaces:
- WindowProtectionCoordinator (@MainActor): start(configuration:), stop(), setConfiguration(_:), setGlobalPause(_:), status(for:), removeAllOverlays().
- 进程通过 bundle ID、launchDate 和 ProcessRegistry 绑定；同应用所有唯一匹配普通顶层窗口共享应用级前台状态。
- MaterialOverlayCoordinator.reconcile(...) 保持 PoC 的失败闭环；requestSubmitted 只能显示处理中/未验证，失败必须是 cannotProtect；不得创建实色 panel。
- 前台撤目标全部 overlay；失焦只对可见、layer 0、唯一匹配窗口使用 behindWindow；生命周期/权限/显示器/Space/睡眠事件使证据过期并重建。
- 部分成功映射为 partialFailure，全部失败映射为 cannotProtect；失败摘要不得含标题或像素。

- [ ] Step 1: 写测试，覆盖前台撤层、后台 attemptBlur、暂停撤层、缺权限、部分窗口失败、PID 世代变化和退出清理。
- [ ] Step 2: 运行对应测试确认失败。
- [ ] Step 3: 迁移 PoC tracker/focus/overlay，去除 fixture-only guard，接入多目标 bundle ID 配置；保留保守 matcher 和 1 秒校准。
- [ ] Step 4: 实现 coordinator：事件后先撤销过期证据，再重枚举、运行 reducer、交给 overlay adapter；管理窗口不得造成焦点循环。
- [ ] Step 5: 运行 WindowProtectionCoordinatorTests 与全量测试。
- [ ] Step 6: 独立审阅并提交 feat: connect focus tracking to protection overlays。

### Task 4: 菜单栏产品壳、权限和生命周期

Files:
- Create Sources/Sensveil/AppDelegate.swift, ManagementView.swift, PermissionCoordinator.swift, Resources/Sensveil-Info.plist.
- Modify SensveilController.swift, Package.swift, scripts/build-apps.sh, README.md.
- Test Tests/SensveilTests/StatusPresentationTests.swift.

Interfaces:
- AppDelegate (@MainActor) 使用 NSStatusItem；菜单提供打开 Sensveil、暂停/恢复保护、退出 Sensveil；关闭管理窗口不退出进程。
- ManagementView 显示 icon/name/bundle ID、开关、即时状态、删除、添加、全局暂停、Accessibility/Screen Recording 入口和 disabled 的“登录启动（首期暂未实现）”。
- 权限请求只由按钮触发；状态变化后刷新并重枚举；拒绝时仍可查看配置。
- StatusPresentationTests 断言 protected、cannotProtect、partialFailure、paused、overFreeLimit 不会误写成已保护。

- [ ] Step 1: 写状态文案和菜单动作测试，确认先失败。
- [ ] Step 2: 实现菜单栏 delegate、管理窗口和权限入口；产品 bundle 使用 LSUIElement=true。
- [ ] Step 3: launch-at-login 保持 disabled，不调用 ServiceManagement。
- [ ] Step 4: 更新 plist、构建脚本和 README，输出 Sensveil.app 与 SensveilFixture.app。
- [ ] Step 5: 运行 swift test --package-path experiments/macos-blur-poc、bash experiments/macos-blur-poc/scripts/build-apps.sh、plutil -lint 和 codesign --verify --strict。
- [ ] Step 6: 手工验证添加两款非敏感 GUI 应用、第三项被阻止、前后台状态、无法保护文案、管理窗口关闭后菜单栏仍运行。
- [ ] Step 7: 独立审阅并提交 feat: ship Sensveil menu bar MVP shell。

### Task 5: MVP 集成验证和文档

Files:
- Create docs/engineering/MVP_VALIDATION.md.
- Modify experiments/macos-blur-poc/README.md, docs/engineering/DEVELOPMENT.md.
- Modify docs/product/PRD.md only to add implementation-status links; never mark unverified blur as passed.

- [ ] Step 1: 运行核心/产品测试和 release 构建，记录实际命令与结果。
- [ ] Step 2: 手工执行至少 20 次前后台切换、目标退出/重启、移动/缩放、最小化/恢复、权限撤回/恢复；多屏、Spaces、全屏、Intel、macOS 14 无条件时记未测。
- [ ] Step 3: 独立审阅 PRD 条件、状态文案和“无法保护”闭环；失败继续修复，未测不得写成通过。
- [ ] Step 4: 运行 git diff --check、全量 swift test、构建/签名检查并提交 docs: record Sensveil MVP validation boundary。

## Verification Commands

swift test --package-path experiments/macos-blur-poc
bash experiments/macos-blur-poc/scripts/build-apps.sh
plutil -lint experiments/macos-blur-poc/Resources/Sensveil-Info.plist
codesign --verify --strict experiments/macos-blur-poc/.build/apps/Sensveil.app
git diff --check

没有视觉实测证据时，最终产品状态仍必须是“无法保护/未验证”；behindWindow 调用成功不等于视觉保护。ScreenCaptureKit、支付、试用和激活仍未实现。
