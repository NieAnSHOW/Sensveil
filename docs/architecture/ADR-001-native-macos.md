# ADR-001：一期采用原生 macOS 技术路线

日期：2026-10-11 · 状态：路线评审通过；模糊渲染路径与支持矩阵待 PoC

## 背景

Sensveil 的价值来自外部应用窗口跟踪、聚焦切换和真实模糊，而不是复杂网页界面。一期 Windows 暂缓，用户明确拒绝以不透明遮罩替代模糊。

## 决策

选择 Swift 6、SwiftUI 管理界面、AppKit 覆盖窗口、NSWorkspace 焦点观察、ApplicationServices AX 窗口跟踪。模糊路径依次验证 NSVisualEffectView behindWindow 与 ScreenCaptureKit + Core Image。最低 macOS 14 与两种 CPU 架构只是建议，需验证。

使用公开 API、独立签名公证分发；先完成 [可行性验证](../engineering/FEASIBILITY_SPIKE.md)，再评审 PRD 和建立产品应用工程。

## 替代方案

- Tauri：可复用未来 Windows UI，但当前仍需原生窗口引擎，增加 Rust/Swift 桥接和 WebView 成本。
- Electron：提供透明窗口和点击穿透等能力，但核心隐私模糊仍需原生，常驻 Chromium 对简单本地工具不划算。
- 实色遮罩：不能满足已确认产品要求，不作为降级。
- 私有窗口 API：发行与系统兼容风险过大，不使用。

## 代价与复审条件

Windows 后续需要独立 UI/平台适配投入；可共享许可协议、商业规则与验收用例。模糊路径、窗口关联和跨应用层级存在未验证风险，原生选型本身不能消除这些风险。

当基础模糊/层级 PoC 失败、平台范围改变或 Windows UI 复用收益成为关键目标时，重新评审本决策。未验证场景不得在 README 或购买页宣传为已支持。

详细依据见 [技术选型](TECH_SELECTION.md)。
