# ADR-002：统一圆角外扩覆盖

日期：2026-10-14 · 状态：用户已批准方案，覆盖与材料实测结果另行记录

## 背景与决策

此前方案要求逐窗取得真实轮廓。合成单窗候选与两种 SCK 过滤路径结果一致，但标准标题窗缺少独立外缘基准，自绘缩放还有 32 个低 alpha 参考像素差异。用户提出扩大遮罩以容纳通用圆角，并确认接受方案及周边小范围模糊。

改用现有 NSVisualEffectView behindWindow 材料，目标窗口矩形向四边外扩，再以统一圆弧路径裁剪材料。默认半径 20pt、每边 8pt；目标标题栏、直角窗口四角与全部内容必须在材料完整覆盖区内。极小窗口半径夹到外扩矩形短边的一半。圆角只控制遮罩外观，不声称匹配目标真实轮廓，不新增设置或配置 schema。

Apple 公开说明窗口圆角随样式变化；macOS 27 的 `containerConcentric` 根据本应用视图容器计算，不是外部窗口轮廓接口。因此不编造按 OS 版本映射的官方数值，也不依赖录屏权限取得圆角。未来改外观参数须重新验证完整包含。

## 几何与层级契约

- `targetBounds` 是窗口身份与跟随证据，`protectionBounds` 是外扩后的实际 panel 矩形，不能混为一项。
- 几何包含验证使用独立光栅参考，检查目标矩形上的覆盖 alpha；不能只检查 panel 大于目标或把角点的数学包含当作实际绘制证据。
- 窗口移动/缩放后立即更新或重建材料与 mask，不在旧新位置之间动画。DPI、显示器、生命周期变化继续沿用既有失效流程。
- 不缩小 panel 来适配屏幕；系统裁剪屏幕外部分时保留原圆角路径。部分屏幕外、跨屏和特殊空间是否受支持仍需实测。
- 相对顺序仍为遮罩在目标之上，非激活、点击穿透、不使用全局置顶。夹层相交以 `protectionBounds` 作保守检测，只有证明无相交的夹层可以忽略；只触及外扩带的真实冲突也失败，未知几何保持失败。
- 用户接受的是外扩带对桌面或目标后方内容的小范围模糊，不能因此模糊位于目标上方的其他应用或改变其前后顺序。

## 代价与验收边界

绕过外部真实轮廓识别，代价是窗口外围多出一圈模糊以及扩大范围引发更多真实层级冲突。20pt/8pt 属于 Sensveil 参数；外观可再评估，隐私不能依靠降低透明度或不透明填充兜底。

这项批准允许实施统一圆角的几何部分，取代 Task 8 的真实轮廓前提。三档模糊、守护文案、安全过渡以及“已保护”仍需要对应材料、层级、输入和时延证据；单元测试或 mask 光栅覆盖不产生像素隐私成功证据。

## 官方依据

- [Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/)：带工具栏与仅标题栏的窗口圆角不同。
- [NSViewCornerRadius](https://developer.apple.com/documentation/appkit/nsviewcornerradius)：macOS 27 容器自适应圆角。
- [CALayer.mask](https://developer.apple.com/documentation/quartzcore/calayer/mask)：mask alpha 控制内容显示比例。
- [CGPath rounded rectangle](https://developer.apple.com/documentation/coregraphics/cgpath/init(roundedrect:cornerwidth:cornerheight:transform:))：每个角为四分之一椭圆。
