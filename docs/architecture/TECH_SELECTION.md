# Sensveil 技术选型

日期：2026-10-11 · 状态：原生 macOS 路线建议；模糊引擎须经 PoC 才固化

## 1. 决策摘要

一期采用 **Swift 6 + SwiftUI + AppKit**。SwiftUI 承载管理与授权界面，AppKit 管理菜单栏、非激活覆盖窗口和系统生命周期；ApplicationServices Accessibility 跟踪外部窗口，NSWorkspace 观察应用级焦点。

模糊渲染有两个候选：先验证无需主动采集像素的 `NSVisualEffectView.behindWindow`；若隐私强度不满足，再验证 `ScreenCaptureKit + Core Image` 按窗口捕获并模糊。**用户不接受不透明遮罩替代模糊。** 两条路线都不能可靠满足时，明确无法保护，回到产品评审。

macOS 14、Apple Silicon 与 Intel 为建议支持基线，尚无真机证据。Windows 一期不实现；未来复用许可协议、权益规则和测试用例，窗口引擎按平台独立实现。

## 2. 框架比较

| 维度 | SwiftUI + AppKit | Tauri 2 | Electron |
| --- | --- | --- | --- |
| 外部窗口/AX/焦点 | 系统 API 直接使用 | 需 Rust FFI 或原生插件 | 需 Node 原生模块或 Objective-C 桥 |
| 真正跨应用模糊 | AppKit/SCK 原生渲染 | WebView 内 CSS blur 无法替代外部窗口模糊 | 网页 CSS blur 同样不能解决外部窗口模糊 |
| 覆盖层/Spaces/输入 | 对 NSPanel/NSWindow 有直接控制 | 特殊行为需原生适配 | BrowserWindow 能穿透与工作区控制，核心仍需原生 |
| 常驻体积与资源 | 最符合轻量菜单栏工具 | WebView + Rust，有额外桥接成本 | Chromium 常驻成本较高 |
| Windows 后续 | UI 与窗口引擎分别开发 | UI 可复用，引擎仍分平台 | UI 可复用，引擎仍分平台 |
| 当前结论 | 推荐 | 若后续 Web UI 复用收益明确，可重评 | 一期无 Chromium 需求，不选 |

不为了尚未排期的 Windows 提前增加 Rust/Node 桥接，也不把 CSS 模糊当作本产品的核心技术能力。

## 3. 组件与数据流

```mermaid
flowchart LR
    UI[SwiftUI 管理界面] --> Config[本地应用配置]
    Rights[试用与离线许可] --> Policy[保护状态机]
    Config --> Policy
    Focus[NSWorkspace 前台事件] --> Policy
    Track[AX 窗口事件与枚举校准] --> Policy
    Policy --> Overlay[AppKit 非激活覆盖层]
    Blur[材料模糊或 SCK + Core Image] --> Overlay
    Overlay --> Status[保护确认与异常状态]
    Status --> UI
    Activate[用户发起联网激活] --> Service[Workers + D1]
    Service --> Rights
```

| 模块 | 职责 | 不承担的职责 |
| --- | --- | --- |
| AppCatalog/Configuration | bundle ID、名称图标、选择与持久化 | 判断许可签名或采集屏幕 |
| FocusMonitor | 发布当前前台 PID/归属与变化事件 | 操作覆盖层 |
| WindowTracker | 窗口归属、几何、可见性和生命周期 | UI 和计费 |
| ProtectionPolicy | 结合配置、焦点、额度、权限计算期望状态 | 直接调用窗口 API |
| BlurRenderer/OverlayCoordinator | 真实模糊、覆盖层位置/层级/撤销和结果确认 | 签发许可或变更权益 |
| PermissionCoordinator | 检测所需权限、引导与恢复 | 自动承诺权限已授予 |
| EntitlementStore | 免费、试用与签名凭证验签，发布有效额度 | 依赖每次在线服务确认 |
| ActivationClient/Service | 用户触发激活、设备绑定及签发 | 收集应用列表或窗口内容 |

这些是逻辑边界，尚未创建同名类。实现时以 PoC 结果细化接口，不为每个名词提前建立空文件。UI/覆盖操作在主线程执行，窗口跟踪、捕获回调与权益更新采用明确并发隔离；具体 actor 接口在实施设计中定义。

## 4. 系统 API 与约束

### 焦点与窗口发现

- `NSWorkspace.didActivateApplicationNotification` 携带 `NSRunningApplication`，适合应用级聚焦规则；启动时也读取当前前台应用，不只等待下一次事件。
- AX 获取 `kAXWindowsAttribute`、位置和尺寸，观察创建、移动、缩放、销毁等通知。不同应用可返回 `kAXErrorNotificationUnsupported`，因此需要低频枚举校准，不能只依赖所有通知都存在。
- `CGWindowListCopyWindowInfo` 可提供窗口 ID、边界与 WindowServer 元数据；Apple 指出生成列表成本较高，仅用作必要校准。
- AX 元素与 CGWindow/SCK 窗口的精确关联无通用强保证；窗口位置匹配的歧义、PID 复用、隐藏窗口与 helper 归属必须实测。
- AX/AppKit 坐标原点、多屏负坐标与像素缩放需统一转换，不能默认主屏原点适用于所有显示器。

### 覆盖窗口

使用不获取焦点、可点击穿透的 `NSPanel/NSWindow` 候选，覆盖目标窗口内容及标题栏。公开 `order(_:relativeTo:)` 可作为相对层级候选，但跨进程实际表现需要验证。

全局置顶并不能满足本需求：它可能把覆盖层盖在无关前台应用上。必须保留目标与遮挡者的正确关系。覆盖层不能改变目标应用前后顺序或形成焦点切换循环。

`canJoinAllSpaces`、`fullScreenAuxiliary` 表示相关窗口行为能力，不等于任意外部应用的全屏、Stage Manager、系统快照都已可靠支持。Mission Control/Dock 缩略图可能显示原始内容，支持矩阵必须单独记录。

### 两条模糊路径

| 项目 | NSVisualEffectView | ScreenCaptureKit + Core Image |
| --- | --- | --- |
| 官方能力 | behindWindow 模糊桌面及其他窗口 | 按应用/窗口过滤屏幕内容，输出本地像素 |
| 优点 | 无需应用主动保存/处理原始截图，路径轻 | 可控制模糊半径与渲染流程 |
| 风险 | 无公开自由 blur radius，材料随系统设置变化 | 录屏权限、采样开销、帧延迟、原始帧处理风险 |
| 关键验收 | 文字不可辨，减少透明度不能使其变实色或弱化 | 不显示原始帧、无采集反馈、准确坐标与层级 |
| 共同限制 | 不改变目标应用真实内容，无法阻止他人直接采集原窗口 | 同左 |

Core Image 候选为 `CIGaussianBlur`，处理边界 clamp/crop，避免透明边缘漏出。原始缓冲仅保留在内存；活动目标停止不必要捕获，失焦时初始化/首帧时序必须计入曝光测量，不能忽略首帧等待成本。

ScreenCaptureKit 自 macOS 12.3 起提供，但较新 API 有各自 availability。Apple 当前示例要求 macOS 15/Xcode 16，不能把示例要求直接推导为整个框架要求；macOS 14 基线仍需编译与真机证明。

## 5. 权限、隐私与发行

- AX 路径需要辅助功能 TCC 授权；调用信任提示后要重新检测，不能把提示出现当成成功。
- SCK 路径另需屏幕录制 TCC。可能需重启应用使授权生效，按实际 API/系统版本提示。
- 材料模糊候选若通过，不额外申请无用途的录屏权限。
- 禁止私有 CGS 窗口管理 API。Mac App Store 沙盒/审核兼容性未研究通过，因此一期选择独立分发。
- 发行使用 Developer ID、Hardened Runtime、Apple 公证及 DMG。稳定 bundle ID/签名身份关系到权限归属，测试签名环境不能代替发布权限测试。
- 只在用户主动检查时访问更新信息；Sparkle 自动更新列为后续选项，首期不增加额外框架。

## 6. 配置、试用与许可

非敏感配置采用 Codable + 版本化本地文件，写入原子替换并保留迁移备份。小型偏好可使用 UserDefaults。设备密钥、试用记录及许可凭证使用 Keychain；不使用云同步作为默认行为。

本地试用不具备绝对防重领能力。永久授权采用签名凭证本地验签，没有强制在线租约；退款与解绑不能使永久离线旧机实时失效。

许可服务建议 **TypeScript + Cloudflare Workers 原生 fetch handler + D1**，无额外服务框架。理由是接口少、运营成本低，D1 可提供数据库级原子条件写入。设备名额依据主库原子写入而非客户端/Worker 先读后写；唯一约束与请求幂等必须通过并发测试。签名私钥使用 Workers Secrets，服务端 Ed25519 与 CryptoKit 交叉验签。

Workers/D1 是待实现验证的服务路线，不是已部署设施。付费用户长期服务成本、备份恢复和密钥运营不能用“免费额度”代替预算。详见 [许可协议](LICENSE_PROTOCOL.md)。

## 7. 工程与验证方向

PoC 通过且 PRD 经评审后再建立 `apps/macos/` 的 Xcode 应用工程；可测试纯逻辑拆到 Swift Package，系统窗口适配留在应用。使用 XCTest/Swift Testing 验证状态机与权益，真机验证窗口层级和权限。未来许可服务放 `services/licensing/`；当前不创建虚构接口或占位服务。

工程初建时以已验证 Xcode 版本、SDK、deployment target 和依赖锁文件固定构建；不能将当前开发机 SDK 自动当成用户最低 OS。首发需 Apple Silicon 与 Intel 运行证据。完整门槛见 [可行性验证](../engineering/FEASIBILITY_SPIKE.md)。

## 8. 官方依据

查阅日期：2026-10-11。官方文档证明 API 能力，不代表本产品组合已经通过实验。

- [应用激活通知](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification)
- [AXUIElement 与 AXObserver](https://developer.apple.com/documentation/applicationservices/axuielement_h)
- [AX 进程信任检测](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
- [CG 窗口列表](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:))
- [NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview)
- [behindWindow 模式](https://developer.apple.com/documentation/appkit/nsvisualeffectview/blendingmode-swift.enum/behindwindow)
- [窗口相对排序](https://developer.apple.com/documentation/appkit/nswindow/order(_:relativeto:))
- [canJoinAllSpaces](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces)
- [fullScreenAuxiliary](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary)
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) 与 [官方采集示例](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [Core Image 滤镜](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/)
- [公证分发](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Tauri 配置](https://v2.tauri.app/reference/config/) 与 [Electron BrowserWindow](https://www.electronjs.org/docs/latest/api/browser-window)
- [Workers Web Crypto](https://developers.cloudflare.com/workers/runtime-apis/web-crypto/) 与 [Secrets](https://developers.cloudflare.com/workers/configuration/secrets/)
- [D1 Database API](https://developers.cloudflare.com/d1/worker-api/d1-database/)、[限制与并发](https://developers.cloudflare.com/d1/platform/limits/)、[读复制一致性](https://developers.cloudflare.com/d1/best-practices/read-replication/)
