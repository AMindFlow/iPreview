# 当前状态

iPreview 在 macOS 15+ Apple Silicon 与 Windows 11 x64 提供原生本地图片与视频图库。图库索引与合集保存在本机应用数据目录。原始媒体日常由应用只读访问，真实重命名遵循 [LIB-011](../specs/official/library.md#lib-011-重命名真实目录和媒体)。

[0.1.0 验收登记册](releases/0.1.0.md)记录已交付的图库、合集、搜索和预览基线。[0.2.0 发布与验收登记](releases/0.2.0.md)记录已交付的预览与列表改进、合集删除、主题与侧栏以及搜索分类标记。[二期分工与 DAG](phase-2-collaboration.md)记录并行合流及验证边界。

## 0.3.0 集成与验收

来源操作和排序、专辑组织与标签搜索、视频作品分层预览以及扩展格式已进入集成候选。专辑组织数据契约、本地完整与简化作品索引、来源操作和文件排序、双端 0.3.0 安装包版本已合入主线。工作包合入状态、候选证据和双端正式发布验收见 [0.3.0 发布与验收登记](releases/0.3.0.md)。

## 安装与交付

- macOS 使用 DMG 或应用 ZIP。macOS 26+ 采用原生液态玻璃，15 使用系统材质。
- Windows 使用每用户 EXE 或完整自包含 ZIP。安装、覆盖升级和卸载按 [PLAT-005](../specs/official/platforms.md#plat-005-首版标准安装包)保留本地资料库。Mac 包采用 ad hoc 签名且未公证，Windows 安装器尚无 Authenticode 签名。
- 当前正式发布为 0.2.0。最终提交、下载、校验值和安装证据见 [v0.2.0 发布记录](https://github.com/AMindFlow/iPreview/releases/tag/v0.2.0)。操作参照[版本发布流程](../workflow/release.md)。

## 后续工作

外部样张提供方与获取方式待确认。PRE-008 的长按切换矩阵和 PLAT-004 的干净 Windows 11 x64 离线验收继续独立跟踪。详见[未完成清单](backlog.md)、[路线图](roadmap.md)与[完整需求](requirements.md)。
