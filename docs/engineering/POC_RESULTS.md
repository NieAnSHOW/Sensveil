# macOS blur PoC results

日期：2026-10-11；2026-10-13 材料观察与 2026-10-14 轮廓探针准备见下方记录。结论：**部分效果得到操作者正向观察，整体未通过**。10 月 13 日两个保留请求对应窗口由单名操作者确认三档都不可读、模糊程度明显不同；该历史观察不代表新轮廓探针版本当前已运行保护。可靠层级、真实轮廓、有效覆盖层下的输入、视觉时延及完整可读性矩阵尚未通过，当前不能进入 MVP。

## 环境与 API 路径

- 当前构建环境：macOS 27.0.1 (26A434)，arm64，Apple Swift 6.2.3；当前 SDK 别名的 SDKSettings 声明 27.0，最终 PoC Mach-O 的 LC_BUILD_VERSION 记录 sdk 26.2、minos 14.0。两者不同，SDK 查询状态仍须核实。
- Package 与构建脚本目标为 macOS 14.0。新 SDK 编译通过不证明 macOS 14 可运行；macOS 14 与 Intel 真机均未测。
- `xcrun --show-sdk-version` 在本机报告 SDK 查找错误；同时保留 SDKSettings 与 Mach-O 的实际记录，不把工具查询失败当运行证据。
- 每个唯一匹配的标准窗口使用 normal level、borderless nonactivating `NSPanel`；透明背景、无阴影、无动画、鼠标穿透、不成为 key/main window。
- 明确材料候选：`NSVisualEffectView.material = .hudWindow`、`state = .active`、`blendingMode = .behindWindow`。2026-10-13 起诊断 app 提供三档候选（standard/`hudWindow`、enhanced/`underWindowBackground`、strongest/`popover`），逐档测，见下文。材料由系统生成，强度不可控；即使属性正确，也不能证明真实文字不可辨。
- 仅使用公开 `order(.above, relativeTo: cgWindowID)` 请求相对层级。后续 CG 列表可用于发现层级错误，但不能确认合成像素、模糊强度、点击成功或视觉呈现时间。
- `.canJoinAllApplications`、`.fullScreenAuxiliary`、`.ignoresCycle` 是待测候选，不代表全屏、Spaces、Stage Manager 或系统缩略图已支持。
- Reduce Transparency 开启即拒绝材料路径并撤层，不能以实色代替模糊。屏幕、Space、焦点、外观和辅助显示设置变化使旧证据过期。
- 用户要求补充独立的录屏权限请求入口：由按钮触发 `CGRequestScreenCaptureAccess()`，用 `CGPreflightScreenCaptureAccess()` 检测；该诊断不采集像素，也不表示 SCK 路线已获可行性放行。

## 已获得的证据与范围

| 检查 | 2026-10-11 结果 | 能说明的范围 |
| --- | --- | --- |
| `swift test --package-path experiments/macos-blur-poc` | 19 个核心 XCTest 测试，0 失败 | 坐标、匹配、状态规则和进程世代；不是 19 项视觉测试 |
| `bash experiments/macos-blur-poc/scripts/build-apps.sh` | release 构建成功；两 app 的 plist lint 与严格签名验证通过；先验证默认 ad-hoc，随后用户授权的本地开发者签名构建也退出 0 | 当前 arm64 主机可构建；minos 14.0 不等于 macOS 14 或 Intel 已运行 |
| 受控 fixture GUI | 3 个合成内容窗口、12/24/48pt 文本可见；sheet 打开/关闭；PoC 初始关闭 | fixture 基础可操作性；未证明窗口映射、模糊或输入穿透 |
| 辅助功能不可用时启用实验 | 诊断报告 AX 未授予、CG/AX 窗口计数均为 0、覆盖请求为 0，显示“无法保护” | F-07 的不可用分支；0 计数来自权限阻断，不能据此判窗口枚举 API 失败 |
| 权限身份排查与恢复 | 系统诊断确认 TCC 保存的旧 ad-hoc 代码要求与当前开发者签名身份不匹配；用户明确允许仅重置 PoC 的 Accessibility/ScreenCapture 项后重新请求并授予；最新 GUI 两项均为 Granted | 原权限不生效原因已定位；恢复后的实际 preflight 已确认。未完成全部拒绝/撤回流程 |
| 独立录屏权限诊断 | 用户主动点击请求并完成系统认证；重签前曾显示录屏 Granted、AX Not Granted；定向重置并重新授权后两项均为 Granted | 仅请求和授权状态传播；无屏幕像素采集，无捕获或保护成功结论 |
| 恢复权限后选择 fixture | 诊断显示 Matched 3 / CG 4 / AX 4；另有 2 项问题：非标准 AXWindow、可见 CG 窗口没有已验证 AX 对应 | 3 个标准窗口实际匹配；重复几何歧义未测，整个快照仍未通过校验 |
| 恢复权限后启用实验 | 显示 Cannot protect，仍需重新验证；覆盖请求为 0 | 当前被非标准/未验证窗口问题阻断；无材料、层级或输入的视觉证据 |
| 2026-10-13 阻断复现（公开元数据，AX 已授权） | 空闲三窗 fixture 为 AX 3 / CG 3、0 问题；加一个 layer 0 无标题辅助窗口即复现 `Matched 3 / CG 4 / AX 4` 加 2 项问题；加一个打开的 sheet 得到 AX 3 / CG 4 | 复现的是窗口分类缺陷，不是映射 API 失败；仍无像素、层级或输入证据 |
| 2026-10-13 分类修复前后对比（活窗口） | 无标题辅助窗口：旧实现 2 个阻断问题、新实现 0 阻断 + 1 排除；sheet：旧 2 阻断、新 0 阻断 + 1 排除；空闲 fixture 两者都是 3/3/3 | 三个已验证窗口不再被单个辅助窗口否决；未验证窗口仍永不进入保护集合。仍无保护成功结论 |
| 2026-10-13 实验准备 | 诊断 app 增加三档材料选择与 200ms 安全过渡；fixture 三个内容窗口保持 12/24/48pt 虚构文本、标题唯一 | 只是可测量实现与参数；未测量可读性、层级、输入或呈现时延 |

Task 1 至 Task 4 的实现已有逐任务独立代码审阅，Task 4 审阅范围对应 `d1f7069`。这类审阅不替代最终二进制的 GUI 验证。录屏诊断入口对应 `22ca4f9`；独立全量审阅由协调者另行执行。本记录没有作者自我放行。

上述历史实验未执行任何屏幕像素捕获。GUI 观察没有完成用于呈现时延的帧采样；当时屏幕数量、分辨率、缩放和刷新率也未形成完整记录，不能推导显示组合支持结论。10 月 14 日另行授权的实际单窗采集见后文。

## 2026-10-13 准备好的三档材料与安全过渡实验（仍未测）

本节保留此前准备阶段的状态：当时只记录为人工评估准备的实现与参数，不产生任何 PASS；没有执行像素采集、可读性观察或视觉计时，评估者人数为 0，全部测量行保持 UNMEASURED。后续运行与操作者失败观察见下方视觉 Gate 记录。改动位于实验基目录 `experiments/macos-blur-poc/Sources/SensveilPoC/`（诊断 app，不是产品库）。

### 三档材料候选

操作者在诊断页 “Material candidate” 逐档切换。三档共用不变参数：

- `NSVisualEffectView`：`state = .active`、`blendingMode = .behindWindow`、`isEmphasized = false`；
- overlay panel：borderless + nonactivating `NSPanel`、`level = .normal`、`ignoresMouseEvents = true`、`hasShadow = false`、`isOpaque = false`、`backgroundColor = .clear`、`animationBehavior = .none`、`hidesOnDeactivate = false`；
- 层级：仅 `order(.above, relativeTo: 目标窗口 CGWindowID)`，`collectionBehavior = [.canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]`（候选行为，不是全屏/Space 支持证据）。

| 档位 | 材料 | 说明 |
| --- | --- | --- |
| standard | `.hudWindow` | 沿用 2026-10-11 的候选 |
| enhanced | `.underWindowBackground` | 与 standard 相邻但系统实现不同的 behind-window 材料 |
| strongest | `.popover` | 兼作过渡锚点（声明值，不是实测结论） |

三档的真实模糊强度排序**未测**：材料外观差异不等于 blur 差异，任何一档都必须单独通过 AC-05 才算可用。若实测显示 `.popover` 并非最强，必须在测量前重新声明过渡锚点，否则过渡就会从较弱状态开始。

### 安全过渡设计（已实现，视觉未测）

选定方案：**双 effect view 叠放**。锚点视图承载 `MaterialTier.transitionAnchor`（声明最强），`alphaValue` 恒为 1，从不淡入；档位视图置于其上、`material` 为所选档，`alphaValue` 在 200ms 内 0→1。因此 panel 从第一帧起就以最强（声明）材料合成，从不存在 `alphaValue = 0` 的透明起点；过渡只是在上层叠加/混合，不会露出未模糊内容。

未采用的另一选项是“在两种材料之间直接切换”：其起始帧等于所选档本身，无法保证起点不弱于终点，故不采用。

- 撤销：焦点变化、几何变化、移层都走 `remove(_:)`，直接拆除 panel 与两个 effect view；动画没有 completion 回调，因此不存在迟到回调误删新层或显示旧文字的问题。
- 减少动态效果（`NSWorkspace.accessibilityDisplayShouldReduceMotion`）：不跨渐变，直接取最终档位。
- 减少透明度（`accessibilityDisplayShouldReduceTransparency`）：现有策略仍在 `reconcile` 直接拒绝材料路径并撤层，因此过渡代码不会执行；若该策略日后改变，此处同样直接取最终状态，不播放动画。
- 仍缺两个独立指标：失焦→安全模糊建立时间，与视觉过渡完成时间。当前只有 API 请求阶段计数（`overlayRequested`/`overlayRemoved`），呈现时延未测，不能算 AC-01。

### F-01 阻断排查（公开元数据实测）

2026-10-11 记录的签名是 `Matched 3 / CG 4 / AX 4` 外加 2 项问题（非标准 AXWindow、可见 CG 窗口没有已验证 AX 对应）。用当前 fixture 与本机公开 API 复测该签名：

| 场景 | AX 窗口 | 层 0 的 CG 窗口 | 观察 |
| --- | --- | --- | --- |
| 空闲的三窗 fixture | 3（全部 AXStandardWindow） | 3 | 干净；与 2026-10-11 的阻断不符 |
| fixture + 打开的 sheet | 3（sheet 不出现在 `kAXWindowsAttribute`） | 4（sheet 为 layer 0 的额外窗口） | sheet 只在 CG 侧可见 |
| 三窗 + 一个无标题（borderless, level 0）辅助窗口 | 4（多出 role AXWindow / subrole AXUnknown） | 4 | **完整复现** `Matched 3 / CG 4 / AX 4` 与 2 项问题 |

根因：旧实现把任何“不认识”的目标进程窗口都升级为**整快照阻断**问题——任何非标准 AX 元素都记 `非标准 AX window`，任何目标 PID 的额外 CG 窗口都记 `可见 CG 窗口没有已验证 AX 对应`；sheet 打开时还会被父窗口的 `kAXChildren` 检查再记一次。因此**一个 layer 0 的辅助窗口（tooltip/help-tag/popover 一类的无标题窗口，或打开中的 sheet）就能否决全部 3 个已验证窗口**，把快照判为需重新验证，`ProtectionReducer` 随之对全部窗口输出 remove，显示 Cannot protect、0 覆盖请求。这与 2026-10-11 观察到的行为一致；那个会话中具体是哪一个辅助窗口已无法从记录还原，但该签名在 2026-10-13 由“单个 app 自有的 layer 0 无标题窗口”完整复现。

修复（仅诊断 app，`Sources/SensveilPoC/WindowTracker.swift`）：分类先于匹配。

- 只有 role AXWindow + subrole AXStandardWindow 才进入匹配与保护集合。
- sheet（父窗口的 AXSheet 子元素）、dialog、floating 与其他未验证 AX 类型记入 `WindowExclusion`，用同一 1pt 几何容差与 CG 窗口配对；非 0 层的 CG 窗口（菜单、状态栏项、tooltip）同样记入排除项。排除项**永不进入保护集合**（fail closed），但不再否决其他已验证窗口，与 TASK 的“成功窗口与失败窗口并存”一致。
- 只有“layer 0、公开可见、且 AX 完全没有身份的 CG 窗口”仍作为阻断问题保留：那才可能是无法解释的真实内容窗口。
- 用修复前后同一份追踪代码对活窗口实测（2026-10-13）：空闲 fixture 两种实现都是 3/3/3、0 问题；无标题辅助窗口场景旧实现 2 阻断问题、新实现 0 阻断 + 1 排除（nonstandardWindow/AXUnknown）；sheet 场景旧实现 2 阻断、新实现 0 阻断 + 1 排除（sheet）。三种场景都未产生像素或可读性证据。

产品的 `Sources/Sensveil/WindowTracker.swift` 仍保留旧分类，属任务 8 集成所有者的范围，本次未改。

### 轮廓能力（公开 API 限制）

公开 API 只给矩形，不给形状：`CGWindowListCopyWindowInfo` 提供 owner PID、CGWindowID、bounds、layer、on-screen、alpha 等矩形/层级元数据；AX 提供 role/subrole、position/size、minimized、title 与子元素关系。没有公开的圆角半径、窗口形状或 mask 轮廓 API，因此**几何矩形 ≠ 真实轮廓**，无法据此剪裁圆角，也不允许用固定半径近似。

| 窗口类型 | 公开信息（本轮实测/现有实现） | 轮廓可得性 |
| --- | --- | --- |
| 普通带标题窗口 | CG layer 0 + bounds；AX AXWindow/AXStandardWindow + position/size | 仅矩形 |
| 无标题/直角窗口 | CG layer 0 + bounds；AX AXWindow/AXUnknown（实测） | 仅矩形 |
| sheet | CG layer 0 + bounds（实测）；AX 为父窗口的 AXSheet 子元素（带 position/size），不在 `kAXWindowsAttribute` | 仅矩形 |
| 自绘/多窗口应用 | 同一 PID 可出现多个 layer 0 窗口；是否导出 AX 窗口取决于该应用 | 未测 |
| 全屏窗口 | 未测 | 未测 |

没有轮廓 API 的情况下，AC-05/任务 8 的真实圆角匹配需要产品裁决或另找公开途径；本轮不实现固定半径替代。

## 证据记录方法

只使用安全 fixture 的虚构文字。每次填写 OS/架构、屏幕数量、分辨率、缩放、刷新率、窗口数量、材料/state、浅深色、减少透明度、高对比、复现步骤与失败范围；不记录设备唯一标识、窗口标题、真实屏幕内容或本机路径。

API 阶段用单调时钟记录 focusReceived、snapshotReady、overlayRequested、overlayRemoved、invalidated 与请求调用耗时。`requestSubmitted` 只表示调用阶段；`NSWindow.isVisible`、CG 层级元数据及 `order` 返回均不是最终合成呈现证据。100 次切换的 p50/p95/max 和新窗首次曝光必须分别填写 API 请求时间与外部视觉测量时间；缺少可靠视觉测量时 AC-01 未测。

视觉证据使用安全 fixture 帧或独立外部观察，记录采样率、不确定性及标题栏/内容边界。可读性在约 50cm、正常缩放下，3 名独立评估者分别读 12/24/48pt 虚构文本；记录各人能否读出。人数不足或材料变实色都不能通过 AC-05。此前准备阶段评估者人数为 0；当前有 1 名操作者先后报告旧版本失败与最新两个窗口的正向效果，尚无满足协议的 3 人独立评估。

## 2026-10-13 视觉 Gate 补测准备与当前阻断

本轮按用户“先补视觉 Gate”的要求运行新版实验 app。**最新两个窗口的三候选得到单名操作者正向模糊观察，整体 Gate 未通过；完整材料评估尚未完成，F-03/F-04/F-05 均未通过整项**。此前失败、授权记录与早先状态快照保留为各检查时点，不能代表最新整体保护结论。

| 本轮检查 | 实际结果 | 范围 |
| --- | --- | --- |
| 准备阶段核心测试与实验构建 | 125 项测试、0 失败，退出 0；`SENSVEIL_INSTALL=0` 的 release 构建退出 0；两 app 的 plist lint、严格 ad-hoc 签名验证与 `spctl` 检查通过 | 仅构建、核心规则及本机执行检查；未替代视觉 Gate，也不是后续诊断改动的验证结果 |
| 实验 app 启动 | 只启动构建出的 fixture 与 PoC；未安装 fixture，未替换已安装的产品 app | 本轮验证对象为实验 app |
| 授权前检查时的权限与窗口诊断 | Accessibility / Screen Recording 均为 Not Granted；选择 fixture 后 Matched 0 / CG 0 / AX 0，1 项问题为 Accessibility unavailable，覆盖请求 0，Experiment Off | 当时受权限阻断；不能判定枚举、层级或材料失败 |
| 输入与布局基线 | fixture 每窗口增加独立、仅保存在内存的输入框；合成字符串 `GATE-INPUT-3` 可见，检查时布局未见裁切 | Experiment Off、无覆盖层；未测 F-04 的失焦、单击穿透、聚焦和首字符输入，也未测 F-05 |
| 新诊断重启前的权限与唯一窗口匹配 | 用户随后授权请求 AX；点击前实际已显示 Accessibility Granted、请求按钮禁用，因而当时没有发起请求。Screen Recording 仍为 Not Granted；重新选择 fixture 后 Matched 3 / CG 3 / AX 3、0 问题、0 排除 | 当时三个唯一标准窗口匹配已复验；重复几何歧义拒绝仍未测 |
| 新诊断重启前首次启用的层级检查 | 3 次覆盖请求、3 次撤层，显示 `Relative overlay order lost` | 应用内层级检查拒绝了该快照；不是完整 F-03 像素实验，具体原因尚未定位 |
| 新诊断重启前的实验与焦点变化 | 关闭再启用后曾显示 Active / unverified、12 次累计 API 覆盖请求；后续工具操作与焦点回到 Codex 后显示 Cannot protect，原因是无关窗口位于覆盖层与目标之间 | 仅界面状态与 API 计数，未确认覆盖层实际显示或像素顺序；这些检查时点未形成稳定层级证据，也不能推断每次都会复现或公开路线不可行 |
| 自动化输入探针 | GUI 自动化向 fixture 输入框追加 `-CLICK`，字符被接受；工具调用后 `NSWorkspace` 报告前台为 Codex | 自动化提供者恢复前台影响了观察，不能作为真实用户单击恢复与输入的 F-04 通过证据 |
| 解锁后重启新诊断与最新权限 | 用户解锁后，通过 UI 退出旧 PoC 并启动新诊断。新 ad-hoc 二进制初始 AX Not Granted；在此前用户授权范围内点击 AX 请求后状态先未变化，检查系统设置期间变为 Granted，具体用户操作未记录。Screen Recording 仍为 Not Granted；重新选择 fixture 后 Matched 3 / CG 3 / AX 3、0 问题、0 排除 | 新诊断已实际运行，AX 与唯一三窗匹配已复验；不能推断具体授权切换操作 |
| 新诊断的 post-order 检查 | batch 为 3 对窗口，3 对均为 `panelMissing`；AppKit `isVisible = true`，CG 全窗口列表存在对应记录但 bounds 为零、layer 为 0，on-screen 列表尚无对应记录 | 只是该 API 检查时点的不同状态；不能把 3 个 `panelMissing` 直接视作 3 个隐私失败 |
| 新诊断的后续常规检查与外部元数据探针 | 后续 3 对均为 ok；每个 panel 的实际 bounds 与期望目标相符，CG 列表中 panel 紧邻目标之前；外部 on-screen 元数据探针也得到 3 个 PoC 覆盖层记录，均匹配 fixture 的 640×592 bounds | 本会话中 `panel.windowNumber` 对应的 CG 记录匹配实际几何；不证明一般 API 契约、真实像素、实际模糊或稳定持续时间 |
| 新诊断界面状态快照 | Experimental overlay active (unverified)，累计 225 次 API 覆盖请求、0 次撤层，该常规检查快照无失败 | 新诊断的运行状态与元数据准备已有证据；F-03 像素、F-04 真人输入、F-05 材料 Gate 均未通过 |
| 隔离修复前的操作者视觉反馈 | 用户明确确认“第一点可读，没效果就是不符合预期，没有模糊效果，即防护没生效” | 当次真实防护结果 FAIL；1 名操作者的失败观察，不是三档材料独立强度或 3 人评估的完成结果 |
| 发布去重修复前的 strongest 运行与层级拒绝 | `.popover` 已选、Experiment On、AX Granted，Matched 3、0 问题；累计 702 次 API 覆盖请求、9 次撤层。Last post-order batch 与 Next natural check 的 3 对均为 `panelMissing`；AppKit `isVisible = true`，CG 全列表对应记录 bounds 为零、layer 为 0，随后锁存 Cannot protect / Relative overlay order lost | 当时状态否决保护并撤层，可解释该次没有防护效果；不证明 `.popover` 本身强度不足，更不证明三档材料全失败 |
| 操作者点击与输入反馈 | 用户此前报告点击与输入没问题；澄清后的首项结果为文字仍可读 | 仅普通点击输入的正向反馈；覆盖层可能已撤除，尚不能证明有效覆盖层下的穿透、撤层与持续聚焦 |

环境：macOS 27.0.1 (26A434)、arm64；`NSScreen` 报告 1 屏，2560×1440 points，缩放 2；`maximumFramesPerSecond = 60` 是系统报告的最大值，不是实际帧采样率。减少透明度、减少动态效果、高对比均为 false；本轮未完成浅/深色组合测量。

10 月 13 日通过合成实验 app 的 GUI 截图与辅助功能树检查基线，当时未进行 SCK 或应用内捕获 API 采集、未捕获私密整屏、未持久化真实内容。合成 GUI 检查与单个操作者反馈不等于 3 人独立可读性评估或呈现时延帧采样；两者仍缺失。10 月 14 日另行授权的单窗 SCK 轮廓采集记录见后文。

窗口失败隔离修复前 AX 曾显示 Granted，最新实验版本的权限状态见下方最终构建记录；本轮未发起录屏权限请求，未重置 TCC，未自动选取证书或绕过系统安全检查。已获得上述无模糊失败和普通点击输入反馈，尚无有效覆盖层下 `GATE-HUMAN` 输入与其他应用遮挡关系的完整证据；层级像素检查、三档材料独立评估与真实轮廓验证也未完成。

新增相对层级请求后的检查与常规校验诊断已完成源码、debug 编译及新一轮 125 项测试（0 失败）；随后 `SENSVEIL_INSTALL=0` 的新诊断 release app bundle 构建退出 0，plist、签名验证与 `spctl` 检查通过，未替换已安装的产品 app。这些检查均完成于最新运行阶段之前，没有因本次运行观察再构建或测试。此前重启前 GUI 工具报告 Mac 已锁定、自动解锁不可用，当时保留旧进程且未尝试解锁；用户解锁后已完成新 PoC 重启和新诊断运行检查，见上表。零 bounds 随后变为匹配几何的时序支持继续研究元数据传播时点，但没有证明它是此前所有层级拒绝的根因。此次仅增加诊断，没有修复引擎行为，也不能据此宣称层级或保护稳定。

发布去重修复前的源码流程存在同一事件重复发布：后台激活先创建覆盖层，随后窗口刷新中的通知校验新层，最终通知又重复校验；选择应用和权限刷新也有重复发布路径。元数据尚未传播时被同一事件立即重复校验并撤层曾作为待验证假设，不能据此认定此前全部失败的根因。

### 发布去重修复后的最新检查

本次只修改 PoCController，拆分协调与状态发布，移除后台激活刷新前的旧快照校验，并将刷新后的重复校验改为仅发布状态。源码重复调用已修正，独立代码审阅未发现前台、未知焦点、睡眠或权限生命周期撤层门槛的回归；层级失败拒绝仍保留。125 项核心测试为 0 失败，但没有直接覆盖 PoCController。随后 `SENSVEIL_INSTALL=0` release 构建退出 0，plist、签名与 `spctl` 检查通过；未替换已安装产品。构建和审阅不证明视觉问题已修复。

新二进制实际重启后 AX 初始 Not Granted，按既有授权点击请求；用户明确反馈“已重新授权”，随后 GUI 显示 Granted。Screen Recording 仍未授予，没有请求录屏、重置 TCC 或选择证书。选择 fixture 得到 Matched 3 / CG 3 / AX 3、0 问题。

启用时 3 次 API 覆盖请求、0 次撤层；后续独立轮询快照为累计 201 次请求、0 次撤层，3 对常规检查均 ok，实际 bounds 匹配且 panel 紧邻目标之前，外部 on-screen 元数据也有 3 个对应记录。仅证明这些元数据检查时点，不证明真实模糊、持续稳定时间或 F-03 像素通过。

之后 GUI 自动化读取合成输入字段，确认 `GATE-HUMAN` 实际存在，并执行 fixture 的 Move 按钮。后续快照为 CG 4 / AX 4、1 个 dialog 排除；常规检查 2 对 ok、1 对 `unrelatedBetween`，随即拒绝全部覆盖层，累计 441 次请求、3 次撤层。失败快照的 expected bounds 仍是移动前几何，因此不能把本次层级拒绝确切归因于 Move；焦点恢复与自动化干扰的限制仍在，不能推断公开 API 路线不可行。字段存在也不能证明它是在有效覆盖层下首次单击输入。

拒绝后已关闭再启用实验，选择 standard / `.hudWindow`（过渡锚点 `.popover`）；当时界面 Active / unverified，累计 444 次请求、3 次撤层，post-order 的 3 对为 `panelMissing`，随后停止 GUI 自动化进行安静人工观察。操作者明确反馈“没有模糊，显示 Cannot protect”。后续检查为 2 对 ok、1 对 `unrelatedBetween`，仍整体撤层，累计 450 次请求、12 次撤层。因此发布去重修复没有恢复本次视觉防护，人工观察已完成且为 FAIL。

### 窗口失败隔离修复与最终实验版本

上述源码与运行证据确认单个窗口的层级失败会通过全局失败锁存撤除其他 2 个校验 ok 的窗口。诊断 PoC 已改为按窗口维护失败状态：失败窗口撤层并锁存，其他窗口继续提交未验证的覆盖请求；前台、未知焦点、睡眠、权限失效等撤层门槛保留。绝对 CG 元数据不可用时，每个尝试中的窗口都必须锁存失败，不允许以重建重试绕过原有全局拒绝语义。独立代码审阅确认该门槛，修复只作用于实验 PoC，不代表有效模糊或产品保护通过。

最终源码执行 125 项测试、0 失败；这些是编译与核心回归证据，没有直接覆盖诊断 PoC 的具体隔离实现。`SENSVEIL_INSTALL=0` 的最终 release 构建退出 0，plist 与严格 ad-hoc 签名验证通过，新 PoC 的 `spctl` 检查退出 0；未替换已安装产品。

已退出旧 PoC 并实际启动最终实验版本，其初始状态为 No target、Experiment Off、AX Not Granted、Screen Recording Not Granted，覆盖请求与撤层均为 0。授权前点击 AX 请求曾未改变状态；随后用户确认重新授权，GUI 复验为 AX Granted、Screen Recording Not Granted。默认 ad-hoc 构建可能重新要求权限，本轮未重置 TCC、自动选择证书或请求录屏。

重新选择 fixture 后 Matched 3 / CG 3 / AX 3、0 问题、0 排除；启用后首个常规检查为 3 对 ok、6 次 API 请求、0 次撤层。之后读取合成字段确认 `GATE-HUMAN` 仍存在，没有编辑输入，再执行 Move。重复该工作流后的快照为 CG 4 / AX 4、1 个 dialog 排除，累计 247 次 API 请求、1 次撤层；状态为 Partial experimental requests (unverified)，2 个提交、1 个窗口无法保护，锁存原因为 `unrelatedBetween`。后续常规检查只含仍持有覆盖层的 2 对，均为 ok；外部 on-screen 元数据确认失败目标没有 PoC panel，另外 2 个目标的 panel 记录存在、几何匹配且紧邻目标之前。

此次实际 API 检查验证了一个失败窗口撤层、另两个窗口的覆盖请求与元数据记录仍保留。失败对已不在持有 panel 的常规检查集合，原失败理由来自锁存记录；不能把两个 ok 当作失败对被重新检查通过。Move、dialog 出现与自动化恢复前台的影响尚未分别隔离，不能证明几何操作本身是原因。绝对 CG 元数据不可用的全窗口锁存仍只有源码审阅证据，未注入实时失败验证；没有完成 100 次切换。

本运行阶段未再次构建或执行测试。完成上述元数据观察后停止所有 GUI 自动化，操作者随后明确反馈两个保留请求对应窗口“有模糊，文字无法读出”。这是 standard / `.hudWindow` 档位与始终存在的 `.popover` 过渡锚点组合下、1 名操作者对本次两个窗口的正向观察；第三个窗口仍锁存层级失败。此前无模糊 FAIL 保留为旧版本历史结果，当前部分正向效果不等于两个窗口已验证受保护，也不等于 F-03/F-04/F-05 整项通过。

操作者随后逐档比较 standard / enhanced / strongest，明确反馈“三档都不可读，模糊程度明显不同”。这是同一场景、两个保留窗口、1 名操作者对实际模糊程度的正向观察，并非只有色调变化；没有将其换算为 blur radius 或量化强度。`.popover` 锚点始终存在，仍是独立材料归因的测量因素，但不否定该组合的实际观察。此后未重新读取 GUI、构建或测试，以保留人工场景；没有录屏请求或 SCK 捕获，3 人评估、其他系统设置、帧时延及轮廓验证均未完成。

### 公开 API 复核与待研究候选

以下为 Apple 官方文档支持的能力边界，不是实际保护或轮廓可行性证据；前文“只给矩形”的结论限于当前 CG/AX 元数据路径，不能据此排除所有公开捕获候选。

| 官方资料 | 可确认的边界与待验证事项 |
| --- | --- |
| [NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview)、[material](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material-swift.property)、[maskImage](https://developer.apple.com/documentation/appkit/nsvisualeffectview/maskimage) | 材料随系统外观变化；公开属性没有实际 blur radius 控制。`maskImage` 接受调用者提供的 alpha mask，不提供外部目标窗口的 mask |
| [SCWindow.frame](https://developer.apple.com/documentation/screencapturekit/scwindow/frame) | 提供窗口矩形，不提供实际圆角或轮廓 |
| [SCContentFilter.init(desktopIndependentWindow:)](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:)) | 默认只选指定窗口；独立窗口内容可包含被其他窗口遮挡的部分，不能视作当前桌面可见形状。子窗、弹窗不能假定自动包含，仍须按 SDK 与系统版本研究 |
| [shouldBeOpaque](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/shouldbeopaque)、[ignoreShadowsSingleWindow](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/ignoreshadowssinglewindow) | 两属性自 macOS 14 可用；`shouldBeOpaque = false`、BGRA 与忽略单窗阴影可作为 alpha 研究候选，但尚未证明得到可用于保护的真实窗口 mask |
| [CIGaussianBlur.radius](https://developer.apple.com/documentation/coreimage/cigaussianblur/radius) | 提供以像素为单位的可控模糊半径；不解决捕获、轮廓、层级、输入或呈现时延问题 |

F-03/F-04/F-05 Gate 未完成，当前未进入 SCK 条件实验。研究候选既不是已验证方案，也不是公开 API 路线不可能的结论。

## 2026-10-14 独立轮廓探针实现与授权阻断

用户已批准仅针对已验证合成 fixture 的手动单窗口轮廓研究及本版本录屏权限请求，详见[轮廓探针提案](CONTOUR_SPIKE_PROPOSAL.md)。该授权独立于 SCK 模糊替代条件，不改变材料路线、产品保护状态或 Task 8 Gate。

诊断 app 增加独立 `ContourProbeCore` 与一次性 SCK 探针：重新验证 fixture 身份、进程世代、AX/CG/SCWindow 唯一映射，拒绝跨屏窗口；透明 BGRA、无阴影/光标/音频，macOS 14.2 起排除子窗。按实际映射校验并在捕获前后限制 4 百万像素；单个在飞请求取消后仍等待返回，权限、进程、屏幕/Space、几何与选择失效使迟到结果丢弃。分析离开主线程，原帧/RGB 仅在任务内存、不显示/保存/上传；只输出中性二值候选，歧义与全不透明图拒绝预览，候选没有保护有效性结论。

10 项合成 alpha 测试经历失败 stub 后全部通过，完整 135 项测试为 0 失败；release 构建、plist、严格 ad-hoc 签名及新 PoC 的 `spctl` 检查通过，独立源码审阅已完成。`SENSVEIL_INSTALL=0`，未替换已安装产品或安装 fixture。测试未完成真实 alpha 采集、所有异步取消/生命周期交错或一般窗口轮廓验证；产品 target 不依赖探针核心。

旧 PoC 已退出、新诊断实际启动：初始为 No target、Experiment Off、AX Not Granted、Screen Recording Not Granted，采集按钮禁用、无中性预览。已在用户授权内手动点击 AX 与录屏请求。后续 AX 已显示 Granted，但用户确认录屏尚未授权；系统录屏列表没有当前 PoC 条目，已在添加选择器中选中当前构建的 app，当时等待用户完成添加、授权及可能的重启，随后发生下节系统拦截。没有执行采集，尚无 alpha 或轮廓结果。严格形状启发式、跨屏/混合 DPI 与 macOS 14 实际运行仍有验证缺口；不把实现或纯测试通过写成轮廓成功。

## 2026-10-14 系统安全阻断（历史检查时点）

用户在录屏授权时报告 app 被系统判为恶意软件并移入废纸篓。具体拒绝原因和被处理的 bundle 尚未确认；当时只读检查仍发现构建目录内 PoC bundle 存在。该时点已停止实验，没有修改系统安全策略、隔离或 TCC，也未自动选择证书。后续用户确认“可以正常使用继续”并授权恢复；不能据此推断先前拦截是误报或确定其原因。

## 2026-10-14 限定轮廓探针实际结果

恢复后实际 GUI 为 AX Granted、Screen Recording Granted，无需新的权限请求；fixture 执行检查通过后启动，选择唯一三窗得到 Matched 3 / CG 3 / AX 3、0 问题。Experiment Off、覆盖请求与撤层均为 0，手动仅采集同一个已验证合成单窗口。源码与构建未因本次运行更改；先前 135 项测试和构建记录仍是此前阶段证据。

| 单次采集 | 映射与统计 | 结果 |
| --- | --- | --- |
| 静止 | 640×592 points → 1280×1184 pixels，比例 2；opaque 1,514,352，partial 364，exterior transparent 804，interior transparent 0，interior partial 52 | UNKNOWN / alpha ambiguous，无轮廓预览 |
| 移动后 | 旧结果因几何变化丢弃；重采尺寸与上述 alpha 计数相同 | UNKNOWN / alpha ambiguous，无轮廓预览 |
| 缩放后 | 旧结果丢弃；690×642 points → 1380×1284 pixels，opaque 1,770,752，其余 alpha 计数与上两次相同 | UNKNOWN / alpha ambiguous，无轮廓预览 |

以上首次版本观察单窗采集、映射与移动/缩放结果失效，真实圆角未验证；只读取聚合统计，没有原图预览或其他应用采集。后续边界分析修正和新采集见下节。

## 2026-10-14 边界 partial 分析修正与两次候选

原先一层邻接判定将前 3 次的 52 个 partial 像素归为 interior。分析改为从外缘连通区域遍历多层 partial 带，并记录 boundary-connected partial；内部透明洞、不连通 partial 和无 opaque 内容仍拒绝候选，不改变保护状态。14 项合成分析测试中，新增 4 个用例先出现 5 个断言失败，修正后全部通过。完整测试首次有 1 个既有日历用例的 2 个断言因使用当前时刻而失败；该用例注入固定工作时段，生产逻辑未改，最终 139 项测试为 0 失败。新 release 构建、plist、严格 ad-hoc 签名和 `spctl` 通过，独立代码审阅完成；`SENSVEIL_INSTALL=0`，产品未替换、fixture 未安装。

实际重启后初始两项权限未授予，按用户授权请求后 GUI 均为 Granted；本轮未重置 TCC、自动选择证书或改变安全策略。选择 fixture 为 3 个标准窗口与 1 个排除 dialog，Experiment Off、0 覆盖请求及撤层，仅进行以下两个静态单窗采集：

| 单次采集 | 统计 | 结果 |
| --- | --- | --- |
| 第 4 次，此前已缩放窗口 | 1380×1284 pixels；opaque 1,770,752，partial 364，exterior transparent 804，boundary-connected partial 364，interior transparent 0，interior partial 0 | UNKNOWN / outer contour candidate / unvalidated，中性轮廓示意可见 |
| 第 5 次，另一已验证窗口 | 1280×1184 pixels；opaque 1,514,352，其余计数同第 4 次 | UNKNOWN / outer contour candidate / unvalidated，中性轮廓示意可见 |

合计 5 次手动采集、2 个 fixture 目标；前 3 次歧义、后 2 次候选。示意仅统一灰色填充二值轮廓，不显示原始 RGB 或原始 alpha；原帧只在任务内存，没有保存或上传。目标切换丢弃旧结果；随后实际点击停止研究，结果文本变为已停止/丢弃，预览消失。新分类器只测了 2 个静态帧，未重测其移动/缩放；此前的几何失效记录不替代这一验证，也未测试全部迟到回调交错。

当前有候选形状证据，没有将真实圆角逐点对照、创建保护 mask 或证明一般窗口轮廓权威性。其他窗口类型、macOS 14/Intel、多屏/混合 DPI、完整层级、交互及视觉时延仍需测量；材料与 Task 8 Gate 不变。

## 必测矩阵

状态为“部分已测”的行只覆盖证据栏明确列出的子项，整行尚未通过；其余为未测。构建/单元测试通过不得替代下表的真实系统行为。

| ID | 试验与复现步骤 | 状态 | 耗时、呈现证据、失败范围 |
| --- | --- | --- | --- |
| F-01 | fixture 唯一几何、完全重复几何；对照 CG/AX 匹配与拒绝 | 部分已测，未通过整项 | 此前 Matched 3 / CG 4 / AX 4 的 2 项问题已复现并按窗口类型修复；本轮最新 GUI 唯一三窗为 Matched 3 / CG 3 / AX 3、0 问题、0 排除。重复几何歧义拒绝未测 |
| F-02 | 三窗同应用，连续 100 次前后台切换 | 未测（需人工评估者/GUI 会话） | fixture 三窗已匹配；无 100 次 API 或实际撤层/呈现样本 |
| F-03 | 两个不同 bounds 的部分交叠 fixture 窗口 + 上层 DiagnosticWindow；改前后顺序 | 部分已测，未通过整项 | 旧版本 2 对 ok、1 对失败仍整体撤层；最终隔离版本实测 1 对锁存失败撤层，另外 2 对保留请求、常规检查与外部 CG 记录匹配。仅证明 API 隔离，三层像素、失败原因隔离及 100 次切换未完成 |
| F-04 | 失焦后一次点击后台窗口、输入字符 | 部分已测，未通过整项 | 操作者报告普通点击输入正常，合成字段 `GATE-HUMAN` 已确认存在；自动化恢复 Codex 前台且有效覆盖层可能已撤除，尚无其下首次单击穿透、聚焦、撤层与无循环的证据 |
| F-05 | 浅/深色、减少透明度、高对比、动态内容 | 本场景单人三候选正向，完整矩阵未完成 | 旧版本无模糊 FAIL；最新 1 名操作者在两个保留窗口确认三档都不可读、模糊程度明显不同。始终存在 `.popover` 锚点，未量化半径；第三个窗口失败，3 人及全部设置矩阵未完成 |
| F-06 | 窗口内容更新、候选捕获路径 | 部分已测，未通过整项 | 独立轮廓探针合计 5 次限定采集：前 3 次歧义，边界分析修正后 2 次静态候选；目标切换与停止研究清除结果。旧分类器下移动/缩放失效已测，新分类器未重跑，未创建保护 mask 或 SCK 模糊替代路径 |
| F-07 | AX 拒绝/撤回/恢复；如获准进入 SCK 再测录屏权限 | 部分已测，未通过整项 | 未授予时明确无法保护且无覆盖请求；用户授权定向重置并重新授予后两项 preflight 为 Granted。完整拒绝/撤回流程未测；未进入 SCK |
| F-08 | 移动/缩放、创建关闭、最小化恢复、重启 | 部分已测，未通过整项 | fixture sheet 打开/关闭、PoC 完整重启已观察；实际映射、旧层、偏移、新窗曝光及其余生命周期未测 |
| F-09 | 双屏、混合 DPI、跨屏、拔插 | 未测（需人工评估者/GUI 会话） | 待记录边界与空区域 |
| F-10 | Spaces、原生全屏、Stage Manager 分别试验 | 未测（需人工评估者/GUI 会话） | collectionBehavior 不是通过证据 |
| F-11 | Mission Control、App Exposé、Dock 缩略图 | 未测（需人工评估者/GUI 会话） | 待记录系统快照原始内容 |
| F-12 | 锁屏、睡眠唤醒、系统权限设置 | 未测（需人工评估者/GUI 会话） | 待记录失效与重建 |
| F-13 | 采集/渲染失败、无图帧 | 未测（需人工评估者/GUI 会话） | 材料无图帧；无实色降级 |
| F-14 | 10 可见窗口；静止与动态；CPU/RSS | 未测（需人工评估者/GUI 会话） | 未采样资源、视觉延迟 |
| F-15 | 截图/录屏/共享捕获目标 | 未测（需人工评估者/GUI 会话） | 仅执行另行获批的合成单窗轮廓采集，未测保护目标的截图/录屏/共享行为，不宣称防截图 |
| F-16 | 正常退出、强制结束、崩溃 | 未测（需人工评估者/GUI 会话） | 待记录是否残留 |

| ID | 验收条件 | 状态 | 证据缺口 |
| --- | --- | --- | --- |
| AC-01 | 100 次切换；p95 ≤150ms、max ≤300ms；首次曝光 | 未测（需人工评估者/GUI 会话） | API 请求与视觉呈现均未完成测量 |
| AC-02 | 三窗、双屏、混合 DPI、共同撤层 | 未测（需人工评估者/GUI 会话） | 缺少双屏实际画面 |
| AC-03 | 一次点击、键盘输入、无错盖、顺序不变 | 部分已测，未通过整项 | 普通点击输入正常的操作者反馈不足以证明有效覆盖层下的交互；最新层级拒绝，三层像素实验未完成 |
| AC-04 | 生命周期无残影/孤立层/持续偏移 | 未测（需人工评估者/GUI 会话） | 最终二进制已运行，但无覆盖层生命周期证据 |
| AC-05 | 3 人独立测 12/24/48pt 与全部系统设置 | 本场景单人三候选正向，完整评估未完成 | 最新 1 名操作者报告两个保留窗口三档都不可读且模糊程度明显不同；第三个失败，3 人协议、各字号独立记录与全部设置组合未完成 |
| AC-06 | 权限/捕获失败明确无法保护，无实色/原帧泄漏 | 部分已测，未通过整项 | 未授予分支明确无法保护且无覆盖请求；定向重置/重新授权恢复已确认。完整拒绝/撤销与捕获失败未测，未进入 SCK |

## 材料 Gate

2026-10-14 最新文案验收后：产品保护过渡工程已完成，固定200ms、完整最强起点、前台整体淡出、可取消且失败立即撤层。192项规则/动画状态测试和生产panel有限自检21/21通过；没有捕获像素，外部动画期间不可读性、视觉平滑度和呈现时延仍需人工验收。详见[过渡实现记录](PROTECTION_TRANSITION_VALIDATION.md)，不能把工程通过当动画隐私Gate通过。

2026-10-14 最新：用户再次明确修正后的三档验收。依据本机已验收 profile 接通守护文案运行时，当前窗口仍需几何/顺序/权限/档位等严格检查后才可成功。186项规则测试与本进程真实panel文案自检16/16通过；未新增捕获或取得跨平台/安全动画/三人发行矩阵证据。以下历史整体Gate说明保留当时范围，最新本机文案范围见[接入记录](BLUR_LABEL_INTEGRATION.md)。

2026-10-14 后续人工反馈：用户明确验收档位实现，但增强视觉上比最强更模糊。修正为标准 `.hudWindow`、增强 `.popover`、最强 `.underWindowBackground`，仅互换上层映射、保留底层 `.popover`，不迁移或更改用户配置。该反馈只确立所测场景的档位相对顺序，修后视觉及其他系统组合仍需复验，安全过渡未验收。下方历史日志中的 enhanced/strongest 名称保持当时含义，不追溯改写。

2026-10-14 最新：用户已人工验收统一圆角并授权继续档位/文案工程。历史 `.popover` 锚点加三档上层材料已接入产品保存后下发；171 项规则与布局测试通过。文案组件实现状态门控，但未验证生产材料继续隐藏文案，不新增成功状态。新产品二进制辅助功能未授予且保持暂停，未取得本轮可读性/输入/时延证据。见[档位与文案记录](BLUR_LABEL_INTEGRATION.md)。

2026-10-14 最新需求及实施：用户批准统一圆角外扩完整包含，Task 8 几何子项已实现；161 项测试通过，材料 mask 光栅完整包含、真实 CG 外扩带冲突 4/4 验证，详见[外扩覆盖验证](EXPANDED_OVERLAY_VALIDATION.md)。真实轮廓独立基准不再作为几何前提；下方材料隐私、外部窗口输入和时延等未测门槛仍有效，不开放成功保护状态。

2026-10-14 后续复验：不相交夹层的过度拒绝已修正，真实 CG 三窗自检验证目标外允许、40 × 120 points 交集拒绝；未知几何仍失败。轮廓两种 SCK 单窗路径在标准标题窗及自绘圆角的静止/移动/缩放六种姿态下均零差异，但标准标题窗独立真值缺失，自绘缩放的独立绘制参考仍差 32 个低 alpha 像素。153 项测试通过，release 产品已安装运行。详见[轮廓与层级复验](CONTOUR_ORDERING_VALIDATION.md)。这些局部结果不放行 Task 8，也不替代下方材料、外部窗口交互和评估者门槛。

当前：**材料局部正向、整体未通过；轮廓已有 2 个静态未验证候选，SCK 模糊替代条件路线 BLOCKED**。10 月 13 日材料观察保留为单操作者局部证据。10 月 14 日合计 5 次限定采集，后 2 次得到中性候选，随后停止研究并清除结果；未创建保护 mask。完整层级、权威真实轮廓、有效覆盖层下的交互、3 人及系统设置矩阵仍缺证据，Task 8 未放行；独立候选不满足或替代 SCK 模糊替代条件。

尚需完成的实验步骤（已执行的子项见上方本轮记录）：

1. 启动 `SensveilFixture`（3 个合成内容窗口，唯一标题 Synthetic Fixture 1–3，内容为 12/24/48pt 虚构文本）与诊断 app `SensveilPoC`；授予 Accessibility；选择 fixture。
2. 记录先决条件：OS/架构、屏幕数/分辨率/缩放/刷新率、浅/深色、减少透明度、高对比、窗口数、材料与 state。缺少这些的记录不算证据。
3. 逐档选择 standard/enhanced/strongest，确认三窗都产生覆盖请求且层级关系保持；对每档由 3 名独立评估者在约 50cm 正常缩放下尝试读出 12/24/48pt 文本。材料外观差异不是 blur 差异，任何一档都要单独达到 AC-05。
4. 过渡：观察启用与切档时的首帧是否立即为锚点（声明最强）材料、约 200ms 内过渡到所选档；另用外部帧采样分别记录“失焦→安全模糊建立”和“视觉过渡完成”两个时间。撤销场景（切换焦点、移动/缩放目标、移除 overlay）逐个试验。
5. 同一次会话中顺带完成 F-03 层级与 F-04 一次点击/输入，因为它们共享同一环境。
6. 逐项标 PASS/FAIL/UNMEASURED；缺少规定评估者或帧采样的项目不能记完整验收通过。已有运行失败据实记 FAIL，其余缺证据的子项保持 UNMEASURED。

材料强度相关的否定结论须先确认对应覆盖层实际有效合成：该前提下某档在 12pt 仍可辨读，才记该档强度失败。若层级拒绝导致撤层，先记本次运行防护失败，不能归因材料；三档独立强度都失败且层级/输入通过，才允许进入 SCK 条件实验。

此前录屏权限按钮是用户要求的手动权限诊断，只请求权限、不捕获内容；10 月 14 日用户另行批准了上方限定的轮廓研究用途。此前重签后两项权限仍未授予；系统诊断确认 TCC 存储的旧代码要求与开发者签名身份不匹配。用户明确授权仅对 `com.nieanshow.sensveil.poc` 的 Accessibility 与 ScreenCapture 执行定向 `tccutil reset`，随后在稳定签名 app 中重新请求并授予；该历史会话的 GUI 确认两项 Granted，不代表本轮新二进制的权限状态。此次历史重置授权不包含其他应用或服务，不自动重置 TCC，不在仓库保存系统日志、代码哈希或证书信息。

此前用户授权的本地开发者签名构建、严格签名验证和 designated requirement 检查已通过；该历史会话恢复授权后 AX/录屏 preflight 均为 Granted。本轮未选择该证书，当前授权状态以补测记录为准。构建脚本默认 ad-hoc，也可通过未提交证书信息的 `SENSVEIL_SIGNING_IDENTITY` 环境变量选择本地身份；这不代表 Developer ID、公证或公开发行已完成。

1. 层级或输入失败：记录 F-03/F-04 失败，撤层、显示无法保护，路线待阻断评审；不能用全局置顶、激活目标或私有 API 补偿。
2. 层级与输入通过，只有材料强度失败：才允许 Task 5 的 SCK 条件实验，另行记录录屏权限和失败范围。
3. 材料、层级与输入通过：继续材料路线，不创建 SCK 模糊替代实现；除独立权限诊断与另行获批的合成窗口轮廓研究外，不请求录屏权限或采集。仍需补齐 OS/架构、系统空间、性能和 3 人可读性证据。

当前支持矩阵：所有 OS/架构/显示/系统空间组合仍未验证。当前待办是解决层级与真实轮廓、补齐有效覆盖层下的交互及完整材料评估；单操作者三候选正向观察不替代发行验收，也不自行授权新增捕获路径。轮廓探针的独立授权仅限上方记载的合成窗口用途。

## 后续放行所需证据

先由 GUI 会话复验诊断 app 修复后的快照校验（2026-10-13 已在公开元数据层面复现并修复该分类缺陷，但整项仍未通过），再补齐 F-01 歧义拒绝及 F-02 至 F-05 验证。只有相对层级与输入通过、材料强度失败，才允许实现 SCK 条件路线。随后补齐 100 次事件/呈现分开测量、10 窗口资源、系统空间和生命周期、macOS 14/Intel/多屏以及 3 人独立可读性评估。完整记录前保留“未具备放行证据”，不降低 PRD 验收门槛。
