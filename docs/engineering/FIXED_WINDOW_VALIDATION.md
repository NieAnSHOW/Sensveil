# 标题栏操作与固定窗口验证

日期：2026-10-14。依据 [TASK](../../TASK.md) 第 11 节本次调整：全局暂停/恢复位于原生标题栏右侧，侧栏固定 210pt，管理窗口内容固定 920 × 700pt，不提供调整大小、全屏和侧栏折叠。

## 实现与自动验证

- 使用右侧 `NSTitlebarAccessoryViewController` 与原生 `NSButton`，订阅保护状态、配置只读状态及语言变化。移除页面中的重复暂停按钮，保留页面共享错误提示。
- 保留隐藏标题与透明顶部，移除全尺寸内容样式及自定义 `sendEvent` 拖动转发，使用 AppKit 原生标题区事件处理。
- 使用固定宽度侧栏及原生 sidebar List，详情表单仍可滚动。生产宿主根视图固定尺寸，`NSHostingController.sizingOptions` 的最小、最大尺寸与 AppKit 限制一致，不恢复旧窗口尺寸，禁用绿色按钮和全屏。

执行命令：

```sh
swift test --package-path experiments/macos-blur-poc --filter ManagementLayoutTests
swift test --package-path experiments/macos-blur-poc
bash experiments/macos-blur-poc/scripts/build-apps.sh
git diff --check
```

3 项布局测试及全量 223 项测试均通过，0 失败。布局测试检查生产窗口固定尺寸、跨页尺寸稳定、标题栏按钮位置与动作、暂停写盘、控制器外部变化、即时中英切换、损坏配置时禁用，以及英文指定时段在 780 × 560pt / 780 × 700pt 宿主中的滚动与固定侧栏。窄尺寸宿主仅用于回归检查，产品窗口仍固定 920 × 700pt。

默认 release 构建、plist 检查、严格 ad-hoc 签名验证及 macOS 执行评估通过；产品已安装并启动，安装脚本确认进程持续运行。未安装实验 fixture。独立代码复核未发现问题，`git diff --check` 退出 0。

## 可见交互边界

更新前 GUI 工具能够读取旧窗口的辅助功能树。更新后通过产品完整路径重连多次均返回 `timeoutReached`，重置工具会话后仍超时；随后进程检查确认安装后的产品仍运行。未据此推定应用无响应或用户锁屏，也未修改系统安全设置。

本轮没有取得更新后的截图或实际鼠标点击证据。自动测试的 `performClick` 证明按钮动作及状态更新，不替代真实鼠标点击与标题栏拖动区的验证；滚动边界断言不替代底部保存栏、关于入口和最后一行内容的可见检查。浅深外观、macOS 14 与 Intel 的实际运行仍待验证。以上界面调整不提供新的模糊隐私强度证据。
