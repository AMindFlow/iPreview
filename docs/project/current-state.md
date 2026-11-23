# 当前状态

iPreview 在 macOS 15+ Apple Silicon 与 Windows 11 x64 提供原生图片和基础视频图库。图库索引与合集保存在本机应用数据目录。原始媒体日常由应用只读访问，真实重命名遵循 [LIB-011](../specs/official/library.md#lib-011-重命名真实目录和媒体)。

[0.1.0 验收登记册](releases/0.1.0.md)记录已交付的图库、合集、搜索和预览基线。[0.2.0 发布与验收登记](releases/0.2.0.md)记录本轮确认的预览与列表改进、合集删除、主题与侧栏以及搜索分类标记。[二期分工与 DAG](phase-2-collaboration.md)记录并行合流及验证边界。

## 安装与交付

- macOS 使用 DMG 或应用 ZIP。macOS 26+ 采用原生液态玻璃，15 使用系统材质。
- Windows 使用每用户 EXE 或完整自包含 ZIP。安装、覆盖升级和卸载按 [PLAT-005](../specs/official/platforms.md#plat-005-首版标准安装包)保留本地资料库。Mac 包采用 ad hoc 签名且未公证，Windows 安装器尚无 Authenticode 签名。
- 正式包和设备验证随相应版本发布记录归档。0.2.0 最终提交、下载、校验值和安装证据见 [v0.2.0 发布记录](https://github.com/AMindFlow/iPreview/releases/tag/v0.2.0)。操作参照[版本发布流程](../workflow/release.md)。

## 二期未完成项

专辑组织界面、标签搜索、视频作品导入与预览、视频格式扩展，以及等待干净 Windows 11 x64 离线验收的包体瘦身仍由[未完成清单](backlog.md)和[二期总任务 #58](https://github.com/AMindFlow/iPreview/issues/58)追踪。[路线图](roadmap.md)记录后续依赖与排期，[完整需求](requirements.md)保留原始范围及逐项映射。
