# Sensveil

Sensveil 是一款面向 macOS 的本地隐私防窥工具：当指定应用失去焦点时，Sensveil 会在其窗口上显示模糊保护层；应用重新获得焦点后，保护层会移除。模糊是产品的核心保护方式；如果无法可靠地应用模糊，Sensveil 应明确显示“无法保护”。

项目当前处于技术可行性验证阶段，尚无正式可下载版本。仓库已有独立的 [macOS PoC 实验和 Sensveil 菜单栏 MVP 壳](experiments/macos-blur-poc/README.md)，提供可重复的测试和 app 构建命令；MVP 可管理最多 2 款应用、暂停和恢复保护、查看即时状态。当前结论仍为 [未具备放行证据](docs/engineering/POC_RESULTS.md)，实际模糊保护待验证时会显示“无法保护”。首期目标平台为 macOS，Windows 暂缓。

## 预期产品规则

- 免费版最多配置 2 款需要防窥的应用。
- 付费版不限制配置数量。
- 新设备首次使用提供 5 天连续试用（共 120 小时），从首次启动本地起算。
- 激活码永久激活：¥19.9 绑定 1 台设备，¥32.9 绑定 2 台设备。
- 首次激活需要联网，激活完成后日常可离线使用。

以上内容是当前需求基线，最终行为以产品文档和技术验证结果为准。

## 文档

- [产品需求文档](docs/product/PRD.md)
- [技术选型](docs/architecture/TECH_SELECTION.md)
- [许可证协议设计](docs/architecture/LICENSE_PROTOCOL.md)
- [可行性验证](docs/engineering/FEASIBILITY_SPIKE.md)
- [macOS PoC 实施计划](docs/superpowers/plans/2026-10-11-macos-blur-poc.md)
- [macOS PoC 实验与运行说明](experiments/macos-blur-poc/README.md)
- [macOS PoC 结果与未测清单](docs/engineering/POC_RESULTS.md)
- [开发指南](docs/engineering/DEVELOPMENT.md)
- [待决策问题](docs/decisions/OPEN_QUESTIONS.md)

## 隐私与安全边界

Sensveil 的目标是本地窗口防窥体验，不是操作系统访问控制、恶意软件防护，也不能保证阻止所有截图、摄像或外部采集方式。窗口识别、失焦监听、屏幕捕获和辅助功能权限等系统能力必须以真机验证结果为准。

激活服务只应处理许可证校验和设备绑定所需的最少信息。请勿在公开 Issue 中提交激活码、设备标识、开发者证书、私钥或包含真实隐私内容的屏幕截图。详见 [安全策略](SECURITY.md)。

## 贡献

当前仓库主要用于需求、设计和可行性验证。提交代码或文档前请阅读 [贡献指南](CONTRIBUTING.md)。

## 许可证

当前仓库采用保留版权声明，详见 [LICENSE](LICENSE)。查看仓库内容不代表获得复制、修改、分发或商业使用授权。
