# iPreview 项目概览

iPreview 是 picosmic 的原生升级，用专辑组织本地图片、视频和音频，并提供类似 macOS「快速查看」的预览体验。首版已在 macOS 和 Windows 交付图片及基础视频功能，音频与 iOS 的后续范围见[完整需求](requirements.md)。

| 平台 | 最低要求 | 技术栈 |
| --- | --- | --- |
| macOS | macOS 15 | Swift、SwiftUI、AppKit、Quick Look |
| iOS | iOS 17 | Swift、SwiftUI、UIKit、Quick Look |
| Windows | Windows 11 x86_64 | C#、.NET LTS、WinUI 3、Windows App SDK，视频使用 `MediaPlayerElement` |

macOS 与 Windows 使用共享 SQLite 结构、迁移脚本和测试样例。iOS 沿用共享数据契约，实机范围随规格确认。
