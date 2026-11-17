# 平台与分发

## PLAT-004 Windows x64 自包含 ZIP

- **要求** Windows 11 x64 发行 ZIP 解压即用。采用 Windows App SDK 的 WinUI 组件包，跟随其声明的传递依赖。保留 .NET 和 Windows App SDK 自包含发布。
- **来源** [Windows 发布瘦身 #26](https://github.com/AMindFlow/iPreview/issues/26)
- **验收** 用同一基线比较依赖和包体积，确认 XAML、PRI 和应用图标完整。在干净的 Windows 11 x64 离线解压启动并完成[实机验收](../../project/acceptance.md#windows-自包含包离线验收)。
