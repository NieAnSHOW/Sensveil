# 开发指南

## 当前状态

仓库在 `experiments/macos-blur-poc/` 的独立 Swift 6/AppKit 包内已有 Sensveil 菜单栏 MVP 外壳、配置规则与窗口协调运行时、全局保护设置（模糊三档/守护文案开关/保护时段）、每周与节假日时段判定、内置中国大陆节假日日历，以及 PoC/合成 fixture。历史测试和三个 app 的 release 构建已在 arm64 主机执行；本轮结果应以最新验证记录为准。[MVP 验证边界](MVP_VALIDATION.md) 记录实际命令与未测项。本机已接入有限范围的材料与守护文案证据，见[接入记录](BLUR_LABEL_INTEGRATION.md)；缺少有效证据时保持“无法保护”。早期历史实验结论仍为 [未具备放行证据](POC_RESULTS.md)。全面免费，不再规划支付、试用和激活；公开发布、Developer ID 签名及公证流程尚未建立。

## 可重复的实验命令

2026-10-14 分栏界面与全面免费改动的 203 项测试、构建安装、GUI 观察及未测项见 [本轮验证记录](SIDEBAR_FREE_APP_VALIDATION.md)。

在仓库根目录执行：

```sh
swift test --package-path experiments/macos-blur-poc
bash experiments/macos-blur-poc/scripts/build-apps.sh
```

测试验证窗口匹配、坐标、状态、进程世代、配置、时段、协调器和菜单动作规则。构建脚本生成 `experiments/macos-blur-poc/.build/apps/` 下的三个 bundle，默认使用 ad-hoc 签名，并将通过 macOS 执行评估的 `Sensveil.app` 安装并启动在 `/Applications/Sensveil.app`。设置 `SENSVEIL_INSTALL=0` 可跳过安装；`SENSVEIL_INSTALL_DESTINATION` 仅接受以 `Sensveil.app` 结尾的绝对路径，父目录必须已存在。包无第三方依赖，需要可用的 Xcode/Swift/macOS SDK；最低构建目标为 macOS 14.0，macOS 14 与 Intel 的实际运行仍未测。

手动启动 PoC 和 fixture，只使用 fixture 的虚构数据；仅产品 app 由构建脚本安装并启动。PoC 初始关闭，目标须显式选择；权限仅由用户按钮主动请求。独立录屏权限诊断不采集像素，也不放行 SCK 路线。ad-hoc 重编可能改变 TCC 身份，应记录最终二进制实际 preflight 结果，不自动重置权限。详细步骤见 [实验 README](../../experiments/macos-blur-poc/README.md)。

需要证书签名时，先取得用户对该用途的授权，再通过 `SENSVEIL_SIGNING_IDENTITY` 显式指定有效身份；脚本不会扫描并自动选用证书，也不会在指定身份失败时回退。`codesign --verify --strict` 只验证包和签名完整性，不能证明证书未吊销或系统允许执行。安装前后都执行 `spctl --assess --type execute`；评估失败或证书被吊销时停止，不修改 Gatekeeper、不清除 quarantine、不重置权限。开发签名不是公证或公开发行凭据，ad-hoc 在启用正常安全策略的设备上也可能被拒绝。

安装在同一父目录中暂存并验证新包，退出安装路径对应的 Sensveil 进程，将旧包重命名备份后替换；拒绝符号链接及身份不是 Sensveil 的既有目标。若启动失败或进程未保持运行，恢复旧包。应用配置和 TCC 授权记录不由脚本删除。安装需要当前用户对目标父目录有写入权限，不使用 `sudo`。

## 产品应用图标

产品图标源文件为 `experiments/macos-blur-poc/Resources/base-logo.png`（1024 × 1024 PNG）。构建脚本通过显式源路径调用 `scripts/build-icon.swift`，保留原构图、透明外边距和颜色，高质量缩放生成 16、32、128、256、512 点的 1× / 2× 共 10 个 iconset 文件；1024 像素版本直接复制源 PNG，再由 `iconutil` 生成 `Sensveil.icns`。不添加背景或圆角，不依赖调用目录。图标仅装入产品 `Sensveil.app`，关于页自动读取同一份图标；菜单栏继续使用原生单色符号。生成文件位于 `.build/`，不纳入版本管理。

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

## 免费应用与界面开发约定

Sensveil 不限制配置应用数量，不设置试用、购买、激活和设备绑定；核心保护与配置无需网络，不创建或更新商业 Keychain 材料。旧商业状态不得参与保护判定，升级保留所有用户配置。详见 [免费使用与离线政策](../architecture/LICENSE_PROTOCOL.md)。

管理窗口采用原生 macOS 左侧一级菜单与右侧页面，防窥应用、保护效果、保护时段、权限、通用位于上部，“关于”固定在左侧底部且同级；布局与保护规则见 [TASK](../../TASK.md)。 窗口按用户指定的 macOS 27 原生设计方向隐藏可见标题，并采用透明顶部与全尺寸内容背景；实现使用 macOS 14 已支持的 AppKit 窗口 API，由系统处理安全区域、红黄绿和系统材质。透明标题区会把鼠标事件传给全尺寸内容，因此窗口仅将系统 `contentLayoutRect` 以上的空白上缘单击事件交给公开 `performDrag(with:)`，由 WindowServer 执行拖动；动态排除红黄绿按钮，内容区、双击、sheet 和全屏继续走原生事件分发，不开启全窗口背景拖动。保留缩放、全屏、关闭窗口不退出及 Cmd-, / Cmd-Q；不自行绘制玻璃，不调用未经确认的新版 API。通用明确登录启动尚未实现。关于从 `Bundle.main` 读取版本与构建号（当前 `0.1.0 (1)`），项目/作者链接仅在用户点击时打开系统浏览器。过渡选择保持隐藏。

语言偏好在通用中选择“跟随系统 / 简体中文 / English”，默认跟随系统，独立持久化并立即刷新用户界面，无需重启；系统任意 `zh` 变体使用简体中文，未支持语言回退英文。应用名称、bundle identifier、技术日志、项目 URL 不翻译，保护数据、草稿、本机时区与 DST 判定不变。全局暂停/恢复放在所有页面标题行最右的安全内容区，避开原生标题栏及拖动命中区，错误提示保持共享可见。关于页使用放大的品牌原图与深色中性展示底板，保持源图构图、透明区域和颜色，并验证浅深外观可辨。

透明顶部与原生窗口交互的观察及未测边界见 [透明窗口验证](TRANSPARENT_WINDOW_VALIDATION.md)。

语言切换、关于展示与布局的本轮证据及待完成项见 [中英国际化与布局验证](I18N_LAYOUT_VALIDATION.md)。

本轮至少验证第三个及更多应用、旧配置保留、六个页面、Bundle 版本、链接及离线行为；测试通过不能代替真实模糊验收。历史验证记录中的免费额度、试用和激活条目已废弃，仅作历史证据保留。
