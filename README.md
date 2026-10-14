# Sensveil

Sensveil 是一款面向 macOS 的本地隐私防窥工具：当指定应用失去焦点时，Sensveil 会在其窗口上显示模糊保护层；应用重新获得焦点后，保护层会移除。模糊是产品的核心保护方式；如果无法可靠地应用模糊，Sensveil 应明确显示“无法保护”。

项目已有原生 macOS 产品实现，仍在技术验证和发布准备阶段，尚无正式可下载版本。仓库已有独立的 [macOS PoC 实验和 Sensveil 菜单栏应用](experiments/macos-blur-poc/README.md)，提供可重复的测试和 app 构建命令；应用不限制配置数量，可暂停和恢复保护、查看即时状态，并已实现全局设置（三档模糊/守护文案开关）、每周与节假日保护时段及离线内置节假日日历（当前仅内置 2026 年官方安排）。早期 PoC 结论为 [未具备放行证据](docs/engineering/POC_RESULTS.md)；后续本机材料与守护文案接入边界见[接入记录](docs/engineering/BLUR_LABEL_INTEGRATION.md)，不代表所有系统和场景通过验收。缺少当前有效保护证据时会显示“无法保护”。首期目标平台为 macOS，Windows 暂缓。

本地开发迭代执行 `bash experiments/macos-blur-poc/scripts/build-apps.sh` 后，将通过 macOS 执行评估的 `Sensveil.app` 安装到 `/Applications/Sensveil.app` 并确认启动。默认使用 ad-hoc 签名，重编后可能需要重新授予辅助功能权限；不会自动选用本机证书或修改系统安全设置。需要只构建不安装时设置 `SENSVEIL_INSTALL=0`。签名和安装规则见[开发说明](docs/engineering/DEVELOPMENT.md)。

## 当前产品规则

- 全面免费，不限制配置应用数量，不设试用、购买、激活或设备绑定。
- 核心保护与配置离线运行；支持范围与实际性能仍以技术验证为准。
- 主窗口采用原生 macOS 左右布局，左侧一级菜单为防窥应用、保护效果、保护时段、权限、通用、关于；右侧显示对应页面。登录启动尚未实现，过渡选择保持隐藏。
- 关于显示应用版本与构建号（当前 `0.1.0 (1)`），提供[项目地址](https://github.com/NieAnSHOW/Sensveil)和[作者 GitHub](https://github.com/NieAnSHOW)。

2026-10-14 免费政策取代旧额度、120 小时试用及激活套餐；旧计划和报告中的商业验收仅为历史记录。

## 文档

- [产品需求文档](docs/product/PRD.md)
- [技术选型](docs/architecture/TECH_SELECTION.md)
- [免费使用与离线政策](docs/architecture/LICENSE_PROTOCOL.md)
- [分栏界面与全面免费应用验证](docs/engineering/SIDEBAR_FREE_APP_VALIDATION.md)
- [可行性验证](docs/engineering/FEASIBILITY_SPIKE.md)
- [macOS PoC 实施计划](docs/superpowers/plans/2026-10-11-macos-blur-poc.md)
- [macOS PoC 实验与运行说明](experiments/macos-blur-poc/README.md)
- [macOS PoC 结果与未测清单](docs/engineering/POC_RESULTS.md)
- [开发指南](docs/engineering/DEVELOPMENT.md)
- [待决策问题](docs/decisions/OPEN_QUESTIONS.md)

## 隐私与安全边界

Sensveil 的目标是本地窗口防窥体验，不是操作系统访问控制、恶意软件防护，也不能保证阻止所有截图、摄像或外部采集方式。窗口识别、失焦监听、屏幕捕获和辅助功能权限等系统能力必须以真机验证结果为准。

应用不依赖商业许可服务，不发送激活、试用或设备绑定请求。请勿在公开 Issue 中提交设备标识、开发者证书、私钥或包含真实隐私内容的屏幕截图。详见 [安全策略](SECURITY.md)。

## 贡献

仓库包含产品实现、需求、设计和可行性验证。提交代码或文档前请阅读 [贡献指南](CONTRIBUTING.md)。

## 许可证

当前仓库采用保留版权声明，详见 [LICENSE](LICENSE)。查看仓库内容不代表获得复制、修改、分发或商业使用授权。
