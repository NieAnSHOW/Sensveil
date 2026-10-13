# 桌面与访达焦点修复

日期：2026-10-13

## 问题与原因

点击桌面或切换到访达时，已有的模糊请求可能被撤回。旧实现要求前台应用同时提供 PID 和 launchDate，才能生成 ProcessInstance。macOS 的 launchDate 是可选属性；访达等应用可以有有效 PID，却没有 launchDate。此时前台身份被误判为未知，Reducer 输出无法保护并清除覆盖层。

## 修复边界

产品焦点改为使用 NSWorkspace.frontmostApplication 的有效正数 PID，每次协调时重新读取当前值，不沿用失效的焦点缓存。保护目标的身份仍要求有效 launchDate，并继续通过 ProcessRegistry 的 generation 与窗口跟踪验证。退出通知在 AdapterRuntime 中显式移除 registry 记录。

PoCCore 增加可选 frontmostPID 输入：存在完整 ProcessInstance 时保留原 generation 匹配；仅在该实例缺失时使用有效 PID 判断焦点。PoC 原有调用保持兼容。未知或非正数 PID 仍输出无法保护。

未新增权限、未特殊硬编码访达、未伪造启动日期、未改变模糊或失败提示策略。

## 回归证据

先加入两个行为回归并在旧实现上运行：已处于桌面前台时启动、目标应用切换至桌面再切回。两项均失败，实际输出 cannotProtect，预期为 attemptBlur；修复后通过。

回归覆盖生产 FocusMonitor → AdapterRuntime → Coordinator 链的启动、应用激活、桌面激活、未知焦点；无效 PID；目标缺失启动日期不创建 tracker；generation 优先匹配；进程退出后即使启动日期相同也重新分配 generation。退出失效回归同样先观察失败后修复通过。

这些测试验证焦点判断、协调意图和覆盖请求生命周期，不构成屏幕像素模糊、窗口层级或真实隐私保护的验收证据。
