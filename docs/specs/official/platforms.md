# 平台分发

## PLAT-005 首版标准安装包

- **要求** macOS 15+ Apple Silicon 提供 DMG，包含 `iPreview.app`、指向 `/Applications` 的入口及安装说明。Windows 11 x64 提供每用户 EXE 安装器，可选择安装目录，创建开始菜单入口及标准卸载项。保留两端 ZIP，Windows 保留 .NET 和 Windows App SDK 自包含发布，不在安装时联网或下载运行时。
- **要求** 安装和覆盖升级仅替换应用文件。应用数据目录与原始媒体独立，安装、升级和卸载均保留索引、合集与媒体。卸载程序只移除安装器登记的文件，不递归删除自选目录中的其他内容。
- **边界** 首版 Mac 应用使用 ad hoc 签名，DMG 尚未通过 Developer ID 签名和 Apple 公证；Windows EXE 尚无 Authenticode 签名。不将本次实机运行结果表述为已认证的互联网分发。
- **来源** 用户确认一期交付并要求标准 DMG 与 EXE／MSI 安装包；[macOS 安装包 #52](https://github.com/AMindFlow/iPreview/issues/52)、[Windows 安装器 #53](https://github.com/AMindFlow/iPreview/issues/53)。
- **验收** 对最终源码记录提交及产物 SHA-256。验证 DMG 可挂载、安装入口及应用签名完整；Windows 安装、覆盖升级与卸载后保留独立测试数据及非安装文件，确认 XAML、PRI、图标和自包含运行时在包内。双端从实际安装位置启动并核对原索引和合集可读。干净 Windows 11 离线环境缺失时，单独记录该限制，不据已有运行时的机器推断通过。

## 构建与安装

在 macOS 上先用 `scripts/package-macos.sh` 生成 ZIP，再用 `scripts/package-macos-dmg.sh <ZIP绝对路径> <DMG绝对路径>` 生成同一个应用的磁盘映像。安装时将应用拖入 Applications，更新前退出应用，卸载时将应用移入废纸篓。

Windows 安装器构建入口与命令见仓库 `scripts/` 和 CI Windows 构建步骤。通过安装器更新同一安装目录；卸载保留本机资料库，重新安装后继续使用。

苹果分发与签名依据：[软件分发打包](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)、[公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution/)。
