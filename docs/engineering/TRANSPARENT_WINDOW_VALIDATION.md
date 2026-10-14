# 透明顶部窗口验证

日期：2026-10-14 · 范围：管理窗口布局、顶部拖动及系统窗口交互

本轮按用户指定的 macOS 27 原生设计方向移除可见传统标题栏：使用 `fullSizeContentView`、隐藏标题、透明标题栏及无分隔线，原生分栏的侧边栏背景延伸至顶部。实现使用 macOS 14 已支持的公开 API，由系统保留安全区域与红黄绿按钮；没有采用未经确认的 macOS 27 专属 SDK 能力。

## 已观察的 GUI 结果

- 没有独立白色顶部横条或可见的 Sensveil 窗口标题；侧边栏顶部背景与下方贯通。
- 红黄绿按钮没有遮盖导航第一行；关于、保护效果和防窥应用页显示正常。
- 点击绿色按钮可进入全屏，按 Escape 恢复成功。
- 临时有界诊断观察到真实顶部按下与拖动事件，以及 CG 窗口位置变化，支持真实窗口顶部拖动。本记录不保存实际坐标或原始事件数据。

透明标题区会将事件传入全尺寸内容，顶部拖动由 `ManagementWindow.sendEvent` 在动态 `contentLayoutRect` 以上的空白上缘处理：仅单次左键按下调用公开 `performDrag(with:)`，排除系统按钮、sheet 和全屏；双击及内容区域继续交给原生事件分发，不开启全窗口背景拖动。

CUA 模拟拖动没有得到稳定的位置变化，此项保留为自动工具验证局限，不能据此宣称模拟拖动全部通过。临时诊断仅用于本轮定位，最终代码已移除事件记录，不保留日志能力。

## 构建与测试

最终停止并行修改后，执行协调者完整重跑以下命令，均退出 0：

```sh
swift test --package-path experiments/macos-blur-poc
bash experiments/macos-blur-poc/scripts/build-apps.sh
```

全量测试 203 项、0 失败。默认构建脚本完成 release 构建、plist 检查、严格 ad-hoc 签名验证、`spctl` 执行评估，并将产品安装至 `/Applications/Sensveil.app`，确认安装后进程启动成功。最终安装后保护效果页显示正常，`codesign --verify --strict` 退出 0，安装进程仍在运行。这些结果不是 Developer ID 签名、公证或公开发行证据。

最终 `AppDelegate` 中对 `diagnosticEventCount`、`drag-diagnostic`、`traceDragEvent` 与 `#filePath` 的检索零命中，确认临时拖动诊断已移除。独立静态代码终审没有发现已确认的 P1/P2 问题；`git diff --check` 退出 0。

## 未测边界

暗色、减少透明度与 macOS 14 实机运行尚未验证。本轮没有新增真实外部模糊、屏幕采集或其他平台的保护证据，也不改变“缺少有效保护证据时显示无法保护”的规则。管理窗口布局与全屏交互检查不等于隐私验收；既有保护范围见 [材料与守护文案记录](BLUR_LABEL_INTEGRATION.md)。
