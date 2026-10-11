# 开发指南

## 当前状态

Sensveil 尚未建立正式产品 macOS 应用工程。仓库包含产品与工程文档，以及 `experiments/macos-blur-poc/` 下的独立 Swift 6/AppKit 实验。该实验的核心测试和两 app 构建已在当前 arm64 主机执行，真实保护仍为 [未具备放行证据](POC_RESULTS.md)。正式产品的发布、Developer ID 签名和公证流程尚未建立。

## 可重复的实验命令

在仓库根目录执行：

```sh
swift test --package-path experiments/macos-blur-poc
bash experiments/macos-blur-poc/scripts/build-apps.sh
```

测试验证纯窗口匹配、坐标、状态和进程世代规则。构建脚本生成 `experiments/macos-blur-poc/.build/apps/` 下的 `SensveilPoC.app` 与 `SensveilFixture.app`，检查 plist，并执行 ad-hoc 签名与验证。实验无第三方依赖，需要可用的 Xcode/Swift/macOS SDK；最低构建目标为 macOS 14.0，macOS 14 与 Intel 的实际运行仍未测。

手动启动两 app，只使用 fixture 的虚构数据。PoC 初始关闭，目标须显式选择；权限仅由用户按钮主动请求。独立录屏权限诊断不采集像素，也不放行 SCK 路线。ad-hoc 重编可能改变 TCC 身份，应记录最终二进制实际 preflight 结果，不自动重置权限。详细步骤见 [实验 README](../../experiments/macos-blur-poc/README.md)。

## 计划工具链

首期技术方向为原生 Swift 6，结合 SwiftUI 和 AppKit；建议 macOS 14 作为最低系统门槛，最终门槛待可行性验证和产品评审确定。工程化前需要确认 Xcode、Swift、签名、公证和分发渠道的版本策略。

## 建立正式产品工程前的验证

应先完成 [可行性验证](FEASIBILITY_SPIKE.md)，至少覆盖：

- 目标应用窗口定位和进程 / 窗口生命周期；
- 窗口失焦与重新聚焦事件；
- 模糊保护层的准确性、层级和窗口跟随；
- 多屏、全屏、最小化、Spaces 与 Stage Manager；
- 辅助功能、屏幕录制等权限被拒绝、撤回和重新授权；
- Safari、终端及 Electron 应用等代表性目标；
- 应用退出、窗口新建、窗口销毁和异常恢复。

## 文档变更检查

文档改动可使用：

```sh
git diff --check
```

同时检查 README 中的文档链接可访问。PoC 构建和核心测试不能代替视觉验收；实际证据与未测项应更新到 POC_RESULTS。正式产品工程建立后，再补充其 Xcode 构建、UI 测试、签名、公证和发布命令。

## 许可证开发注意事项

首次激活需要联网，激活后日常可离线使用。许可证验证和设备绑定应与界面层解耦，并遵循 [许可证协议设计](../architecture/LICENSE_PROTOCOL.md)；不要将激活码或设备私钥写入日志、测试夹具或提交历史。
