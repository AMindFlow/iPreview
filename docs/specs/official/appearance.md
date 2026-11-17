# 应用视觉标识

## UI-001 应用图标

- **要求** 白色圆角方形底承载蓝紫星云球与星芒。环绕星球的轨道、行星和媒体符号采用蓝青渐变，小尺寸保留星球和轨道的轮廓。macOS 和 Windows 使用由同一可编辑 SVG 主稿导出的平台图标。
- **来源** [星云轨道图标 #16](https://github.com/AMindFlow/iPreview/issues/16)，用户提供的轨道构图及蓝青配色参考
- **验收** 审阅矢量主稿和常用尺寸在浅、深背景上的呈现。打包后在 Finder、Dock、Windows 资源管理器和任务栏核对新图标。


## 设计决定

- [SVG 主稿](../../../shared/assets/AppIcon.svg)是两端共同来源。macOS 将多尺寸 ICNS 放入应用包。Windows 将多尺寸 ICO 嵌入可执行文件，同一个 ICO 随包提供给窗口和任务栏。
