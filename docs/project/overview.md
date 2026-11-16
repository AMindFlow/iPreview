# iPreview 项目概览

iPreview 是三端原生视觉媒体管理应用，用专辑组织本地图片和视频，并提供类似 macOS「快速查看」的预览体验。

| 平台 | 最低要求 | 技术栈 |
| --- | --- | --- |
| macOS | macOS 15 | Swift、SwiftUI、AppKit、Quick Look |
| iOS | iOS 17 | Swift、SwiftUI、UIKit、Quick Look |
| Windows | Windows 11 x86_64 | C#、.NET LTS、WinUI 3、Windows App SDK，视频使用 `MediaPlayerElement` |

三端使用 SQLite，共用数据库结构、迁移脚本和测试样例。功能范围和验收条件随规格确认。
