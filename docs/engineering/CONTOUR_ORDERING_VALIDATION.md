# 轮廓精度与第三窗层级复验

日期：2026-10-14。结论：已修正不相交夹层的过度拒绝，并完成真实 CG 元数据复验；轮廓完成两路径几何一致性对照，但独立外形精度门槛尚未通过，Task 8 不开始。

后续需求已调整：用户批准 [ADR-002](../architecture/ADR-002-expanded-rounded-overlay.md) 的统一圆角外扩完整覆盖，允许开始 Task 8 几何子项。本文保留此前真实轮廓验证结果，32 个低 alpha 差异与独立真值缺口不再作为外扩几何方案的前提；其他视觉门槛仍保留。

## 范围与环境

本机 macOS 27.0.1（26A434）、Apple Silicon、所测显示器比例 2。仅创建和采集合成窗口，单窗白名单、无音频、无持续流、无自动权限请求。原帧、RGB、原始 alpha 仅在本机内存，不保存或上传；输出仅几何和计数。没有安装 fixture，也没有将实验候选接入产品保护 mask。

## 轮廓精度

新增 `ContourCoverageComparison`，将候选二值轮廓与相同像素网格的参考比较。任何非零参考 alpha 都计入应覆盖区域，不设忽略阈值；分别统计漏覆盖、多覆盖和顶部标题栏区域漏覆盖。新增 3 项测试实际经历 stub 失败后通过。

标准标题窗使用公开 `NSView.cacheDisplay(in:to:)` 作为独立绘制参考。实际返回全不透明矩形，四角均不透明，不能表达 WindowServer 的圆角剪裁，因此该参考无效，804 个差异（标题栏 402）不能解释为真实漏内容。Apple 的该 API 文档描述的是视图及子视图绘制，不保证窗口合成外缘。

另用 `SCContentFilter(display:including: [source])`，只包含同一已核实的本进程合成窗口，裁取该窗区域，排除桌面、Dock、菜单栏和阴影，与 `desktopIndependentWindow` 路径交叉比较。NSWindow 全局 frame、CG frame、显示器比例、采集前后身份和几何均校验，输出不超过 400 万像素。两路径同属 ScreenCaptureKit，只证明所测合成与位置映射一致，不能作为独立权威轮廓保证。

| 窗口 / 姿态 | 像素尺寸 | 显示器路径非零参考像素 | 漏覆盖 / 多覆盖 | 标题栏参考 / 漏覆盖 |
| --- | --- | --- | --- | --- |
| 标准标题窗 / 静止 | 960 × 784 | 751836 | 0 / 0 | 61038 / 0 |
| 标准标题窗 / 移动后 | 960 × 784 | 751836 | 0 / 0 | 61038 / 0 |
| 标准标题窗 / 缩放后 | 1100 × 884 | 971596 | 0 / 0 | 69998 / 0 |
| 自绘圆角 / 静止 | 960 × 720 | 689176 | 0 / 0 | 无标题栏 |
| 自绘圆角 / 移动后 | 960 × 720 | 689176 | 0 / 0 | 无标题栏 |
| 自绘圆角 / 缩放后 | 1100 × 820 | 899944 | 0 / 0 | 无标题栏 |

六次显示器参考均四角透明且有不透明主体。自绘圆角的独立 `cacheDisplay` 参考在静止、移动后零差异；缩放后有 32 个参考像素未被候选覆盖，均为 partial alpha，最大 24，不透明像素漏覆盖为 0。这是本地绘制与采集合成的边缘光栅差异，尚未证明零漏覆盖；未调高阈值、膨胀候选或替换成固定圆角。自绘参考中的固定半径只属于正控绘制，不用于识别标准窗口。

显示器路径首次尝试因临时 `CGColor` 被 unsafe 引用而退出 133，该次不计验证证据。修正为持有强引用并延长到异步采集结束后，带最终全局坐标检查的有限自检退出 0，结果如上；没有保存原帧。

## 第三窗层级

根因：两个 coordinator 原先仅检查 panel 与 target 索引之间是否存在非自有窗口，没有核对夹层几何。新共享逻辑使用同一份 CG 顺序及 bounds，已证明无交集（含仅边缘相切）的夹层不拒绝；真实交集、无效/未知几何、pair 缺失或反转仍失败。PoC 显示夹层 bounds 与 intersection，并保留导致锁存失败的行，避免后续仅剩成功 pair 时掩盖失败。

真实 CG 自检创建三个本进程非激活 normal panel，确认顺序为 overlay → third → target，每种姿态在第一次 100ms 采样时已观测到请求顺序及几何：

| 姿态 | third 与目标交集 | 判定 | 结果 |
| --- | --- | --- | --- |
| third 位于目标外 | 无 | `ok` | 符合预期 |
| third 移入目标 | 40 × 120 points | `unrelatedBetween` | 符合预期 |
| third 再移出 | 无 | `ok` | 符合预期 |

第三阶段仅验证纯判定随几何恢复；coordinator 的真实冲突仍锁存，必须结束当前 attempt（例如关闭再开启实验）后才能重试。Post-order 仍只诊断，等待下一次自然检查，不能把 compositor 尚未发布 panel 元数据的瞬间当成持续失败。历史第三窗日志不含夹层 bounds，无法追溯其是否确有交集。本轮不证明三张外部 fixture 窗的视觉层级、模糊或一次点击交互通过。

## 可重复命令与结果

在仓库根目录运行，依赖本机已有录屏权限；权限缺失只记录跳过，不自动请求：

```sh
swift test --package-path experiments/macos-blur-poc
experiments/macos-blur-poc/.build/debug/SensveilPoC --validate-ordering
experiments/macos-blur-poc/.build/debug/SensveilFixture --validate-contours
bash experiments/macos-blur-poc/scripts/build-apps.sh
```

本轮完整 XCTest：153 项、0 失败。层级回归先观察不相交/边缘相切失败，修正后层级与产品适配的 13 项聚焦测试通过；真实层级自检退出 0、3/3 符合预期。轮廓自检退出 0 表示有限流程结束，不表示外形验收通过，必须阅读计数与 `UNVALIDATED` 结论。Release 构建、三个 bundle plist 和严格 ad-hoc 签名检查通过，产品执行检查通过并安装、运行于 `/Applications/Sensveil.app`。未选择证书、重置 TCC、清除隔离或关闭安全检查。

两条实现 lane 互换代码进行独立审阅。审阅发现产品元数据不可用分支撤层后没有锁存失败，新增同一 attempt 再次 reconcile 的断言实际失败；修正后同 attempt 保持失败，结束后允许重试，最终 153 项重新全部通过。另将 fixture 参考位图的四百万像素检查提前至 AppKit 分配前，并保留分配后的实际尺寸检查。两项修正均经另一位作者只读复核，没有新的确认阻断；这不是产品视觉放行。

安装后产品 GUI 显示辅助功能已授予，既有配置仍可见；没有编辑配置或采集产品目标。新 PoC 经执行检查后启动，No target、Experiment Off、0 覆盖请求，辅助功能与录屏均为 Not granted，Capture once 禁用。没有再次请求权限；debug 自检的已有权限不能移作新 release PoC 的授权证据，因此修后三张外部 fixture 窗的 GUI 复验仍未执行。

本机 `spctl` 返回 `accepted`，同时注明 `override=security disabled`；本轮未修改该系统状态。因此这里只记录当前主机允许执行，不把它当作正常 Gatekeeper 策略、公证或发行安全验收证据。

## 剩余门槛

标准标题窗需要独立于这两种 SCK 路径的真实外缘基准；自绘缩放后的低 alpha 差异也需解释并证明不会裁掉可见内容。外部 fixture 三窗的修后层级与输入、3 人独立可读性、呈现时延、其他窗口类型、macOS 14、Intel、多屏及混合 DPI 仍缺证据。此次结果不改变材料 Gate，不开放“已保护”或守护文案。

官方依据：[视图缓存](https://developer.apple.com/documentation/appkit/nsview/cachedisplay(in:to:))、[显示器单窗白名单](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(display:including:))、[单窗过滤](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:))。
