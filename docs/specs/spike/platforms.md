# 平台与分发后续需求

## PLAT-001 iOS 原生体验

- **要求** iOS 保留在路线图，平台基础见[项目概览](../../project/overview.md)。纳入哪些媒体、导入来源和触屏预览交互随 iOS 规格确认。
- **来源** [总体需求 #3](https://github.com/AMindFlow/iPreview/issues/3)，已确认的首版分期计划
- **验收** 明确覆盖范围后，在 iOS 实机从可安装构建验证首批流程。

## PLAT-002 旧版浏览器与局域网工作流

- **要求** 旧版浏览器默认只在本机访问。面向受信局域网场景可显式开放，局域网客户端无须账号即可浏览和编辑应用内组织数据，例如使用 iPhone Safari。主机配置和源文件操作限本机。新版是否承接浏览器入口，以及是否需要鉴权和如何限制编辑，待确认。
- **来源** [总体需求 #3](https://github.com/AMindFlow/iPreview/issues/3)，旧版安全文件操作与局域网访问规格
- **验收** 先确认访问模式、授权边界和关闭行为。若保留，用受信和未授权设备验证访问限制及移动端流程。

## PLAT-003 旧版桌面安装与升级体验

- **边界** 新原生 DMG／EXE 安装器由 [PLAT-005](../official/platforms.md#plat-005-首版标准安装包)交付；本条仍保留旧 Electron／Squirrel 数据发现、兼容升级、自动升级与相关旧版工作流。
- **要求** 记录原 Electron 版本的 macOS、Windows 桌面分发、安装升级和旧数据发现，包括 Windows 旧 Squirrel 安装形态，以及旧版已提出的安装向导要求（语言、目录选择、确认及进度）。原生安装器已单独确定；兼容哪些旧版本和旧版升级方式仍待定。旧库数据迁移见 [LIB-005](library.md#lib-005-旧库迁移备份与恢复)。
- **来源** [总体需求 #3](https://github.com/AMindFlow/iPreview/issues/3)，旧版桌面分发与桌面体验补缺规格
- **验收** 确认分发形态后，用实机验证全新安装、支持版本的升级及保留库数据。使用测试工作区验证。

## PLAT-004 Windows 组件包瘦身

- **要求** 将 `Microsoft.WindowsAppSDK` 2.6.5 元包替换为同版本 `Microsoft.WindowsAppSDK.WinUI` 组件包。保留 `SelfContained=true`、`WindowsAppSDKSelfContained=true` 和 Windows x64 ZIP；保留 WinUI 声明的传递依赖，不做 .NET 裁剪或 Native AOT。解压后无需网络和额外运行时即可运行。
- **来源** [瘦身 #26](https://github.com/AMindFlow/iPreview/issues/26)、[候选 PR #27](https://github.com/AMindFlow/iPreview/pull/27)。
- **验收** 用同一基线构建替换前后 Release，对比 ZIP 和解压后总字节数及缩减比例；核对 NuGet／产物中 Windows ML、AI、SDK 搜索、Widgets 去留，以及 XAML、PRI 和图标。在干净 Windows11 x64 断网环境记录系统版本、预装运行时及完整核心流程，验收通过后才合入。宿主机已有运行时的断网测试不能代替干净环境验证。交付真实 ZIP、SHA-256、提交和 PR 及结果，构建估值不作为实际结果。
- **范围** 当前候选已做构建与依赖对照，干净环境验收尚未完成，仍属待验收项。标准安装器不自动包含此分支。
