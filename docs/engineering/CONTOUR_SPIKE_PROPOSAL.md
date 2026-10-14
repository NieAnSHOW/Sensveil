# 合成窗口真实轮廓研究提案

日期：2026-10-13；2026-10-14 更新。状态：此前完成 5 次限定采集；本轮增加可重复的精度与层级自检，实测结果见[精度与层级复验](CONTOUR_ORDERING_VALIDATION.md)。两种单窗采集路径在静止、移动、缩放后一致，但标准标题窗独立外形基准仍缺失，自绘缩放存在 32 个低 alpha 参考像素差异。权威轮廓与产品可行性仍未定。依据：[Task 8 计划](../superpowers/plans/2026-10-13-protection-effects-and-schedule.md)、[当前实验记录](POC_RESULTS.md)。

## 研究问题

2026-10-14 后续：用户已批准 [ADR-002](../architecture/ADR-002-expanded-rounded-overlay.md)，产品改为统一圆角外扩完整覆盖。此真实轮廓探针保留为独立研究，不再要求其通过后才能实施产品几何；原有单窗采集授权范围不因此扩大。

当前操作者观察到两个保留窗口上的三个候选均不可读且模糊程度明显不同；这不是材料强度失败，不触发既有 SCK 模糊替代条件。另一个窗口仍因层级错误被拒绝。

本提案单独研究：公开单窗口图像的透明通道，能否可靠提供合成 fixture 的外轮廓，以补齐真实圆角信息？不改变既有材料路线，不修改产品保护状态，也不放行第三窗或 Task 8。

## 有限探针

- 仅接受当前已验证的 SensveilFixture 进程与唯一 CG/AX 窗口。用进程世代、PID、CGWindowID 和 bounds 对应 SCWindow；拒绝其他应用、覆盖层、未知窗口、歧义匹配和已经变化的目标。
- 用户明确同意此用途后，手动请求当前诊断二进制的屏幕录制权限；权限实际授予才开放“采集一次合成窗口轮廓”。按钮一次只处理一个窗口，不创建持续捕获流、音频输出或后台定时采集。
- 使用 macOS 14 的 `SCScreenshotManager.captureImage` 和 `SCContentFilter(desktopIndependentWindow:)`。BGRA、透明输出、排除单窗阴影、关闭光标与音频；按 `contentRect`、`pointPixelScale` 和实际图像尺寸校验映射，不能假设固定 2 倍或省略标题栏。
- 原始帧只短暂存在本机内存，不显示、不保存、不上传。只输出中性的外轮廓示意与计数；内部区域统一填充，不能显示可能含文字形状的原始 alpha。
- 最多一个在飞请求；捕获前按输出 width × height 校验不超过 4 百万像素，返回后再次校验图像尺寸。停止研究、进程变化、几何或显示环境变化后丢弃结果；迟到回调不发布旧图。
- 先静止采一张，再在受控移动与缩放后逐次重采；实际未测的 DPI、系统版本及窗口类型继续标未测。层级和点击问题独立处理，不用图像 mask 冒充遮挡关系正确。

## 证据与失败条件

### 2026-10-14 精度复验范围

按用户本轮要求，增加显式的一次性 fixture 自检：仅采集本进程创建的合成窗口，在静止、移动后、缩放后分别将候选与独立绘制参考比较，统计漏覆盖、多覆盖与标题栏区域差异。标准标题窗的公开视图缓存只有在包含真实 compositor 外形时才有资格作为外缘参考；若不包含圆角，记录参考无效，不以固定半径补齐。已知自绘形状只作为比较链路的正控，不代表标准标题窗或任意外部应用通过。此自检不自动请求权限，不保存或显示原帧、RGB 或原始 alpha；只输出几何与计数。没有产品保护状态变更。

若视图缓存不能表达系统外形，可在同一有限自检中增加显示器合成路径交叉对照：使用 `SCContentFilter(display:including: [source])`，白名单只含同一已校验的本进程合成窗口，按该窗区域裁取，不包含其他应用、桌面或菜单栏；仍为单窗、无音频、无持续流、仅内存。该对照验证两种公开过滤路径的一致性，不冒充独立于 ScreenCaptureKit 的权威外形保证。

第三窗层级复验同时记录夹层窗口与目标的 CG bounds 和交集：只有已证明无相交的第三窗可以忽略；真实交集、无效或未知几何、缺失或反转的层级继续失败。元数据检查通过不能代替模糊强度和交互验收。

检查外缘连通透明区域、非矩形边界、抗锯齿带和内部透明性。不得拟合固定圆角半径；不得把内部透明洞误当外部区域而裁掉可能包含内容的部分。

整图不透明、背景被压平、边界歧义、几何映射不一致或与 fixture 的实际外形不符，记录失败或无法判定，不创建保护 mask。正向结果也只适用于实际测试的合成窗口与环境；单张图不提供运行时轮廓新鲜度保证，不产生“已保护”或守护文案。

此探针的交付是可行性结论。只有公开路径、失败处理和支持范围经验证后，才另行设计产品接入。

## 2026-10-14 实现与当前证据

独立 `ContourProbeCore` 仅由诊断 app 使用，没有加入产品 target 依赖。10 项合成 alpha 分析测试先观察 stub 失败，随后全部通过；完整 135 项测试为 0 失败。release 构建、plist、严格 ad-hoc 签名及新 PoC 的 `spctl` 检查通过，使用 `SENSVEIL_INSTALL=0`，没有替换已安装产品或安装 fixture。独立代码审阅已检查采集范围、原帧处理和失效逻辑；这些证据不替代真实采集、异步取消与生命周期的人工验证。

实现每次重新校验 AX/CG 与 SCWindow 的唯一对应、fixture bundle/可执行文件、PID 和进程世代；仅接受完全位于同一显示器内的窗口，按实际 `contentRect`、比例与尺寸校验，捕获前后均执行 4 百万像素上限。透明 BGRA、无单窗阴影、无光标和音频；macOS 14.2 起显式排除子窗。最多一个在飞请求，取消后仍保持忙碌直到返回；迟到结果重新校验权限、屏幕/Space、几何、进程与选择，失效即丢弃。

原帧和 RGB 只短暂保留在任务内存，后台分析后释放，不写文件、日志或预览。只允许显示内部统一填充的中性二值轮廓候选；全不透明或歧义结果拒绝候选预览。结果始终标记 candidate / unvalidated，不创建保护 mask、不改变保护状态。严格形状启发式可能拒绝可用形状；跨屏/混合 DPI 未支持，捕获 alpha 也没有通用权威轮廓保证。

系统拦截前曾退出旧 PoC、启动新诊断 app：初始 No target、Experiment Off、AX 与 Screen Recording 均为 Not Granted，“采集一次”禁用且无预览。按用户授权点击请求后，AX 曾显示 Granted，录屏仍未授予；系统设置选中当前 app 后用户报告安全拦截，当时停止授权与采集。后续用户确认可正常使用并授权继续，最新采集结果见下节。材料 Gate 与 SCK 模糊替代条件不因此改变，Task 8 仍未放行。

## 2026-10-14 系统安全阻断

用户在录屏授权过程中报告 app 被系统判为恶意软件并移入废纸篓。具体原因及被处理的 bundle 身份尚未确认；当时只读检查发现构建目录中的 PoC bundle 仍存在，不能用此否定报告或推断系统误报。该检查时点已停止实验，没有清除隔离、关闭安全检查、重置 TCC 或自动选择证书。之后用户明确反馈“可以正常使用继续”，实验在既有正常安全策略下恢复；这不解释先前拒绝原因。

## 2026-10-14 实际单窗采集

恢复后的 GUI 显示 AX 与 Screen Recording 均为 Granted，无需再次请求；fixture 经执行检查后启动，唯一三窗匹配为 CG 3 / AX 3、0 问题。Experiment Off、0 覆盖请求与撤层下，仅手动采集同一已验证合成窗口 3 次：静止、移动后及缩放后。移动和缩放均使旧结果被丢弃；实际尺寸和 alpha 计数见[实验记录](POC_RESULTS.md)。

最初三次均返回 UNKNOWN / alpha ambiguous，没有中性轮廓预览。原帧和 RGB 仅在任务内存分析，没有显示、保存或上传，也没有采集其他应用；该阶段真实圆角未验证。

随后将原来只检查一层邻接的 partial 分析改为从外缘连通区域遍历多层 partial 抗锯齿带，内部透明洞及不连通 partial 的拒绝仍保留；没有改变保护状态。14 项合成分析测试通过，完整测试先暴露依赖当前时间的既有日历测试问题，注入固定日期后最终 139 项为 0 失败，生产日历逻辑未改。新 release 构建、签名及执行检查通过，独立代码审阅完成；这些测试不覆盖全部捕获取消与生命周期交错。

新二进制实际启动并完成两项权限授予后，在 Experiment Off 下又静态采集两个已验证 fixture 窗口，分别为 1380×1284 与 1280×1184 pixels。每次 partial 364 均归为 boundary-connected，interior partial 和 interior transparent 均为 0，返回 UNKNOWN / outer contour candidate / unvalidated；中性统一灰色填充轮廓示意可见，不含原始 RGB 或原始 alpha 纹理。切换目标丢弃旧结果，随后停止研究清除结果及预览。本次只验证两个静态帧，未用新分类器重跑移动/缩放采集；没有创建或安装保护 mask，也未放行 Task 8。

下一步须比较候选与真实外缘，继续验证层级、交互、评估者与时延；其他窗口类型、系统版本、多屏/混合 DPI 和全部异步交错仍缺证据。透明角像素与候选不构成一般外部窗口权威轮廓保证。

## 官方依据

[截图 API](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)、[单窗口过滤](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:))、[透明输出](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/shouldbeopaque)、[排除阴影](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/ignoreshadowssinglewindow)。Apple 未保证捕获 alpha 是所有外部窗口的权威轮廓；该缺口正是本探针要验证的问题。
