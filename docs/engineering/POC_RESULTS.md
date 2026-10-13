# macOS blur PoC results

日期：2026-10-11；2026-10-13 更新见下方“准备好的三档材料与安全过渡实验”与“F-01 阻断排查”小节。结论：**未具备放行证据**。核心规则、可重复构建及部分 fixture/权限诊断已有证据；真实模糊、相对层级、输入与视觉时延尚未测得。当前不能据此进入 MVP，也不能判定公开 API 路线失败。

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

本次实验未执行任何屏幕像素捕获。GUI 观察没有完成用于呈现时延的帧采样；屏幕数量、分辨率、缩放和刷新率也未形成完整记录，不能推导显示组合支持结论。

## 2026-10-13 准备好的三档材料与安全过渡实验（仍未测）

本节记录为人工评估准备的实现与参数，不产生任何 PASS。本次没有执行像素采集、可读性观察或视觉计时；评估者人数仍为 0，全部测量行保持 UNMEASURED，原因是需人工评估者/GUI 会话。改动位于实验基目录 `experiments/macos-blur-poc/Sources/SensveilPoC/`（诊断 app，不是产品库）。

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

视觉证据使用安全 fixture 帧或独立外部观察，记录采样率、不确定性及标题栏/内容边界。可读性在约 50cm、正常缩放下，3 名独立评估者分别读 12/24/48pt 虚构文本；记录各人能否读出。人数不足或材料变实色都不能通过 AC-05。当前评估者人数：0。

## 必测矩阵

状态为“部分已测”的行只覆盖证据栏明确列出的子项，整行尚未通过；其余为未测。构建/单元测试通过不得替代下表的真实系统行为。

| ID | 试验与复现步骤 | 状态 | 耗时、呈现证据、失败范围 |
| --- | --- | --- | --- |
| F-01 | fixture 唯一几何、完全重复几何；对照 CG/AX 匹配与拒绝 | 部分已测，未通过整项 | 权限恢复后 Matched 3 / CG 4 / AX 4；2 项非标准/未验证窗口问题。2026-10-13：已用公开元数据复现该签名并定位为窗口分类缺陷，诊断 app 已按类型排除辅助窗口（见上文 F-01 排查），但仍需 GUI 会话复验整项；重复几何歧义拒绝未测 |
| F-02 | 三窗同应用，连续 100 次前后台切换 | 未测（需人工评估者/GUI 会话） | fixture 三窗已匹配；无 100 次 API 或实际撤层/呈现样本 |
| F-03 | 两个不同 bounds 的部分交叠 fixture 窗口 + 上层 DiagnosticWindow；改前后顺序 | 未测（需人工评估者/GUI 会话） | 尚无真实覆盖层，未测三层像素与无关应用遮挡 |
| F-04 | 失焦后一次点击后台窗口、输入字符 | 未测（需人工评估者/GUI 会话） | 尚无真实覆盖层，未测穿透、聚焦、撤层、无循环 |
| F-05 | 浅/深色、减少透明度、高对比、动态内容 | 未测（需人工评估者/GUI 会话） | 候选 hudWindow/active；未产生视觉模糊证据；可读性评估 0 人 |
| F-06 | 窗口内容更新、候选捕获路径 | 未测（需人工评估者/GUI 会话） | 材料无捕获；未创建 SCK 路径 |
| F-07 | AX 拒绝/撤回/恢复；如获准进入 SCK 再测录屏权限 | 部分已测，未通过整项 | 未授予时明确无法保护且无覆盖请求；用户授权定向重置并重新授予后两项 preflight 为 Granted。完整拒绝/撤回流程未测；未进入 SCK |
| F-08 | 移动/缩放、创建关闭、最小化恢复、重启 | 部分已测，未通过整项 | fixture sheet 打开/关闭、PoC 完整重启已观察；实际映射、旧层、偏移、新窗曝光及其余生命周期未测 |
| F-09 | 双屏、混合 DPI、跨屏、拔插 | 未测（需人工评估者/GUI 会话） | 待记录边界与空区域 |
| F-10 | Spaces、原生全屏、Stage Manager 分别试验 | 未测（需人工评估者/GUI 会话） | collectionBehavior 不是通过证据 |
| F-11 | Mission Control、App Exposé、Dock 缩略图 | 未测（需人工评估者/GUI 会话） | 待记录系统快照原始内容 |
| F-12 | 锁屏、睡眠唤醒、系统权限设置 | 未测（需人工评估者/GUI 会话） | 待记录失效与重建 |
| F-13 | 采集/渲染失败、无图帧 | 未测（需人工评估者/GUI 会话） | 材料无图帧；无实色降级 |
| F-14 | 10 可见窗口；静止与动态；CPU/RSS | 未测（需人工评估者/GUI 会话） | 未采样资源、视觉延迟 |
| F-15 | 截图/录屏/共享捕获目标 | 未测（需人工评估者/GUI 会话） | 未执行像素采集；权限诊断不算捕获实验，不宣称防截图 |
| F-16 | 正常退出、强制结束、崩溃 | 未测（需人工评估者/GUI 会话） | 待记录是否残留 |

| ID | 验收条件 | 状态 | 证据缺口 |
| --- | --- | --- | --- |
| AC-01 | 100 次切换；p95 ≤150ms、max ≤300ms；首次曝光 | 未测（需人工评估者/GUI 会话） | API 请求与视觉呈现均未完成测量 |
| AC-02 | 三窗、双屏、混合 DPI、共同撤层 | 未测（需人工评估者/GUI 会话） | 缺少双屏实际画面 |
| AC-03 | 一次点击、键盘输入、无错盖、顺序不变 | 未测（需人工评估者/GUI 会话） | 缺少三层与输入实验 |
| AC-04 | 生命周期无残影/孤立层/持续偏移 | 未测（需人工评估者/GUI 会话） | 最终二进制已运行，但无覆盖层生命周期证据 |
| AC-05 | 3 人独立测 12/24/48pt 与全部系统设置 | 未测（需人工评估者/GUI 会话） | 0 人；无隐私效果证据 |
| AC-06 | 权限/捕获失败明确无法保护，无实色/原帧泄漏 | 部分已测，未通过整项 | 未授予分支明确无法保护且无覆盖请求；定向重置/重新授权恢复已确认。完整拒绝/撤销与捕获失败未测，未进入 SCK |

## 材料 Gate

当前：**UNMEASURED（未测）**。两项权限已实际授予；2026-10-11 阻断快照的窗口分类缺陷已于 2026-10-13 复现并在诊断 app 中修复（见上文 F-01 排查），但整项仍需 GUI 会话复验，且 F-03/F-04/F-05 完全没有实测证据，SCK 条件路线仍不允许执行。该状态既不是“材料通过无需 SCK”，也不是“基础层级/输入失败”：还没有足够证据做这两种判断。

已准备好的实验步骤（每个都需要 GUI 会话与人工操作者，本次未执行）：

1. 启动 `SensveilFixture`（3 个合成内容窗口，唯一标题 Synthetic Fixture 1–3，内容为 12/24/48pt 虚构文本）与诊断 app `SensveilPoC`；授予 Accessibility；选择 fixture。
2. 记录先决条件：OS/架构、屏幕数/分辨率/缩放/刷新率、浅/深色、减少透明度、高对比、窗口数、材料与 state。缺少这些的记录不算证据。
3. 逐档选择 standard/enhanced/strongest，确认三窗都产生覆盖请求且层级关系保持；对每档由 3 名独立评估者在约 50cm 正常缩放下尝试读出 12/24/48pt 文本。材料外观差异不是 blur 差异，任何一档都要单独达到 AC-05。
4. 过渡：观察启用与切档时的首帧是否立即为锚点（声明最强）材料、约 200ms 内过渡到所选档；另用外部帧采样分别记录“失焦→安全模糊建立”和“视觉过渡完成”两个时间。撤销场景（切换焦点、移动/缩放目标、移除 overlay）逐个试验。
5. 同一次会话中顺带完成 F-03 层级与 F-04 一次点击/输入，因为它们共享同一环境。
6. 逐项标 PASS/FAIL/UNMEASURED；没有评估者或没有帧采样的项保持 UNMEASURED，不能记为通过。

材料强度相关的否定结论只能来自实测：某档在 12pt 下仍可辨读即为该档失败；三档都失败且层级/输入通过，才允许进入 SCK 条件实验。

录屏权限按钮是用户新增要求的手动诊断例外，只请求权限，不捕获内容。此前重签后两项权限仍未授予；系统诊断确认 TCC 存储的旧代码要求与开发者签名身份不匹配。用户明确授权仅对 `com.nieanshow.sensveil.poc` 的 Accessibility 与 ScreenCapture 执行定向 `tccutil reset`，随后在稳定签名 app 中重新请求并授予；最新 GUI 已确认两项 Granted。此次授权不包含其他应用或服务，不自动重置 TCC，不在仓库保存系统日志、代码哈希或证书信息。

用户授权的本地开发者签名构建、严格签名验证和 designated requirement 检查已通过；恢复授权后 AX/录屏 preflight 均为 Granted。构建脚本默认 ad-hoc，也可通过未提交证书信息的 `SENSVEIL_SIGNING_IDENTITY` 环境变量选择本地身份；这不代表 Developer ID、公证或公开发行已完成。

1. 层级或输入失败：记录 F-03/F-04 失败，撤层、显示无法保护，路线待阻断评审；不能用全局置顶、激活目标或私有 API 补偿。
2. 层级与输入通过，只有材料强度失败：才允许 Task 5 的 SCK 条件实验，另行记录录屏权限和失败范围。
3. 材料、层级与输入通过：继续材料路线，不创建 SCK 文件；除用户主动使用独立权限诊断外，不请求录屏权限，仍需补齐 OS/架构、系统空间、性能和 3 人可读性证据。

当前支持矩阵：所有 OS/架构/显示/系统空间组合未验证。当前推荐：继续受控材料实验，保留否定结论的可能，不实现产品额度、试用或激活。

## 后续放行所需证据

先由 GUI 会话复验诊断 app 修复后的快照校验（2026-10-13 已在公开元数据层面复现并修复该分类缺陷，但整项仍未通过），再补齐 F-01 歧义拒绝及 F-02 至 F-05 验证。只有相对层级与输入通过、材料强度失败，才允许实现 SCK 条件路线。随后补齐 100 次事件/呈现分开测量、10 窗口资源、系统空间和生命周期、macOS 14/Intel/多屏以及 3 人独立可读性评估。完整记录前保留“未具备放行证据”，不降低 PRD 验收门槛。
