# 统一圆角外扩覆盖验证

日期：2026-10-14。用户批准范围见 [ADR-002](../architecture/ADR-002-expanded-rounded-overlay.md)。Task 8 的圆角几何子项已实现；其余三档、文案、动画及成功保护状态仍待对应 Gate。

后续用户明确“圆角已验收，可以继续做模糊档位与文案”。圆角按此次人工验收记录完成；继续范围见[档位与文案接入](BLUR_LABEL_INTEGRATION.md)。该反馈不替代模糊可读性或安全动画的验收。

## 实现

`RoundedOverlayGeometry` 保留原目标矩形，另算每边外扩 8pt 的覆盖矩形；默认圆弧半径 20pt，极小窗口夹至覆盖短边一半。拒绝无效、非有限或浮点精度不足以表达扩张的几何。产品与诊断 PoC 都用扩大后的 panel，并在 NSVisualEffectView 上安装 `CAShapeLayer` 圆弧 alpha mask，保持 behindWindow 材料、非激活、点击穿透和相对层级，不填充实色窗口。

目标移动/缩放后重建对应 panel；mask 在 layout、进入窗口、backing 属性变化时更新路径和比例，关闭隐式动画。屏幕外部分没有缩到屏幕内再重算圆角。第三窗检查使用实际外扩矩形，仍保守拒绝相交或未知几何，真实失败保持锁存。PoC 分别显示目标和覆盖 bounds。

## 自动化与本机证据

几何 stub 的 4 项测试实际观察到 3 项失败；实现后通过。覆盖层集成测试先观察到 panel 未扩大及外扩带冲突未拒绝的 3 个断言失败，修正后通过。

- 纯圆弧路径在 1/2/3 倍比例、整数与半物理像素偏移、1×2pt 极小窗、37.25×51.5pt 小数尺寸、640×592pt 含标题栏矩形下，所有目标参考像素 alpha 都为 255，遮罩外角为透明。
- 产品实际安装的材料视图 `layer.mask` 用 `CALayer.render(in:)` 独立光栅化，在 layout/resize 后及 1/2/3 倍采样下，目标矩形内 alpha 全为 255，未发现漏角。这个检查验证 mask，不等于 WindowServer 上实际 NSVisualEffectView 的模糊强度证明。
- 产品适配回归检查扩大 frame、移动/缩放关闭旧 panel、负坐标屏幕边缘保留外扩尺寸、仅外扩带第三窗拒绝、未知元数据及真实冲突锁存。
- 完整 `swift test --package-path experiments/macos-blur-poc`：161 项、0 失败。

有限真实 CG 自检 `experiments/macos-blur-poc/.build/debug/SensveilPoC --validate-ordering` 退出 0；同一快照观测到 overlay → third → target，panel 256×196pt、target 240×180pt：

| third 姿态 | 与扩大矩形交集 | 结果 |
| --- | --- | --- |
| 覆盖区域外 | 无 | `ok` |
| 目标内重叠 | 48×120pt | `unrelatedBetween` |
| 只触及外扩带，不碰目标 | 4×120pt | `unrelatedBetween` |
| 再移出 | 无 | `ok` |

4/4 符合预期，不读取屏幕像素、不请求权限。最后一项只说明纯几何判定可恢复，coordinator 的真实冲突仍需结束当前 attempt 后重试。

本机 macOS 27.0.1（26A434）、Apple Silicon。Release 脚本构建、三个 bundle plist 与严格 ad-hoc 签名通过；产品完成当前主机执行检查并安装启动于 `/Applications/Sensveil.app`，fixture 未安装。系统原有 `spctl` 状态为 `override=security disabled`，本轮未改系统安全设置，执行允许不代表正常 Gatekeeper 或发行验收。

安装后的产品 GUI 显示既有配置和辅助功能授权，设置页已改为外扩方案说明。窗口结果仍明确显示模糊尚未验证、无法确认保护；本轮没有修改用户配置或录制用户目标内容。

独立审阅实际读取共享几何、产品和 PoC 两个 coordinator，确认目标/覆盖矩形分离、扩大区域参与第三窗检查、mask 的 layout/backing 更新以及无成功保护升级，未发现本轮新增确认 bug。审阅未独立重跑测试，不把主代理的测试或 GUI 结果扩大为真实材料安全证明。

## 验证边界

已完成的是统一圆角的路径、完整包含、运行时 frame 与扩大范围层级契约。没有新增录屏用途或产品捕获依赖，没有把 `requestSubmitted` 改成“已保护”。真实材料在裁剪边缘的隐私强度、外部三窗交互、呈现时延、混合 DPI/跨屏、sheet、全屏及其他系统空间仍需实测。此前真实轮廓独立真值与 32 个参考边缘差异保留为历史研究，不再作为这个几何方案的前提。
