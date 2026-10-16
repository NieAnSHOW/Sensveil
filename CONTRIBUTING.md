# 贡献指南

Sensveil 已有原生 macOS 产品与 PoC，仍在兼容性和发布验证阶段。可重复命令见[开发指南](docs/engineering/DEVELOPMENT.md)；请不要把演示代码或未经验证的系统行为描述为已发布功能。

Sensveil 全面免费，不限制配置应用数量，不再规划商业许可、试用或激活。仓库采用 [MIT License](LICENSE)，欢迎提交问题、文档改进和代码贡献。

## 开始前

1. 先阅读 [README](README.md) 及相关产品、架构文档。
2. 涉及用户行为、系统权限或免费使用政策的变更，先更新对应 PRD 或 ADR，再修改实现。
3. 使用公开的 Apple 文档核对系统 API，记录最低 macOS 版本和真机验证条件。

## 提交约定

- 分支默认使用 `codex/` 前缀；如任务已有明确分支名，以任务约定为准。
- PR 描述应说明行为变化、验证方法和已知限制。
- 不提交真实设备标识、私钥、开发者证书、个人隐私截图或本机绝对路径。
- 不提交依赖安装产物、构建产物和本地 Xcode 用户数据。
- 模糊保护必须保持为模糊体验；如果系统能力失败，应显示无法保护，不得静默降级为不透明遮挡。

## 验证

代码变更运行 `swift test --package-path experiments/macos-blur-poc`，产品构建运行 `bash experiments/macos-blur-poc/scripts/build-apps.sh`（仅验证构建时设置 `SENSVEIL_INSTALL=0`）。文档变更至少执行 `git diff --check` 并检查链接、全面免费规则和平台范围是否与 PRD 一致。新增系统能力后，需要在真实 macOS 环境记录窗口识别、失焦切换、多屏、全屏、Spaces 和权限拒绝等结果。

## Issue 与 PR

请使用仓库模板提交问题。安全漏洞不要公开发布，参见 [SECURITY.md](SECURITY.md)。较大的功能或架构调整建议先通过 Issue 与维护者讨论范围。

提交贡献时，请确保你有权提供相关内容，并同意将贡献按本项目的 MIT License 授权。引入第三方代码或资源时，保留其必要的版权与许可声明，并确认许可证兼容。
