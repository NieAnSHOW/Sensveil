# 开发指南

## 当前状态

仓库在 `experiments/macos-blur-poc/` 的独立 Swift 6/AppKit 包内已有 Sensveil 菜单栏 MVP 外壳、配置/免费额度规则与窗口协调运行时，以及 PoC/合成 fixture。当前 59 个测试和三个 app 的 release 构建已在 arm64 主机执行；[MVP 验证边界](MVP_VALIDATION.md) 记录实际命令与未测项。真实模糊仍未验证，材料请求状态保持“无法保护”；历史实验仍为 [未具备放行证据](POC_RESULTS.md)。发布、Developer ID 签名、公证、支付、试用和激活流程尚未建立。

## 可重复的实验命令

在仓库根目录执行：

```sh
swift test --package-path experiments/macos-blur-poc
bash experiments/macos-blur-poc/scripts/build-apps.sh
```

测试验证窗口匹配、坐标、状态、进程世代、配置、免费额度、协调器和菜单动作规则。构建脚本生成 `experiments/macos-blur-poc/.build/apps/` 下的三个 bundle，默认使用 ad-hoc 签名，并将通过 macOS 执行评估的 `Sensveil.app` 安装并启动在 `/Applications/Sensveil.app`。设置 `SENSVEIL_INSTALL=0` 可跳过安装；`SENSVEIL_INSTALL_DESTINATION` 仅接受以 `Sensveil.app` 结尾的绝对路径，父目录必须已存在。包无第三方依赖，需要可用的 Xcode/Swift/macOS SDK；最低构建目标为 macOS 14.0，macOS 14 与 Intel 的实际运行仍未测。

手动启动 PoC 和 fixture，只使用 fixture 的虚构数据；仅产品 app 由构建脚本安装并启动。PoC 初始关闭，目标须显式选择；权限仅由用户按钮主动请求。独立录屏权限诊断不采集像素，也不放行 SCK 路线。ad-hoc 重编可能改变 TCC 身份，应记录最终二进制实际 preflight 结果，不自动重置权限。详细步骤见 [实验 README](../../experiments/macos-blur-poc/README.md)。

需要证书签名时，先取得用户对该用途的授权，再通过 `SENSVEIL_SIGNING_IDENTITY` 显式指定有效身份；脚本不会扫描并自动选用证书，也不会在指定身份失败时回退。`codesign --verify --strict` 只验证包和签名完整性，不能证明证书未吊销或系统允许执行。安装前后都执行 `spctl --assess --type execute`；评估失败或证书被吊销时停止，不修改 Gatekeeper、不清除 quarantine、不重置权限。开发签名不是公证或公开发行凭据，ad-hoc 在启用正常安全策略的设备上也可能被拒绝。

安装在同一父目录中暂存并验证新包，退出安装路径对应的 Sensveil 进程，将旧包重命名备份后替换；拒绝符号链接及身份不是 Sensveil 的既有目标。若启动失败或进程未保持运行，恢复旧包。应用配置和 TCC 授权记录不由脚本删除。安装需要当前用户对目标父目录有写入权限，不使用 `sudo`。

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

同时检查 README 中的文档链接可访问。构建与规则测试不能代替视觉验收；当前产品证据与未测项更新到 MVP_VALIDATION，历史 PoC 证据保留在 POC_RESULTS。SwiftPM app 封装命令不等于 Xcode 产品工程或发行流程；后续仍需建立 UI 测试、Developer ID 签名、公证和发布命令。

## 许可证开发注意事项

首次激活需要联网，激活后日常可离线使用。许可证验证和设备绑定应与界面层解耦，并遵循 [许可证协议设计](../architecture/LICENSE_PROTOCOL.md)；不要将激活码或设备私钥写入日志、测试夹具或提交历史。
