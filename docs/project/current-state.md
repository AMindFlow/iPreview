# 当前状态

iPreview 在 macOS 15+ Apple Silicon 与 Windows 11 x64 提供原生本地图片与视频图库。图库索引与合集保存在本机应用数据目录。原始媒体日常由应用只读访问，真实重命名遵循 [LIB-011](../specs/official/library.md#lib-011-重命名真实目录和媒体)。

[0.1.0 验收登记册](releases/0.1.0.md)记录已交付的图库、合集、搜索和预览基线。[0.2.0 发布与验收登记](releases/0.2.0.md)记录已交付的预览与列表改进、合集删除、主题与侧栏以及搜索分类标记。[二期分工与 DAG](phase-2-collaboration.md)记录并行合流及验证边界。

## 0.3.0 范围与验收

0.3.0 包含来源操作、文件排序、专辑组织、分组与标签搜索、两种本地作品索引及分层预览，以及带 LibVLC 本地回退的格式扩展。合集删除与主题选择延续 0.2.0 行为。工作包合入状态、候选证据和双端正式发布验收见 [0.3.0 发布与验收登记](releases/0.3.0.md)。

## 0.3.1 交付

0.3.1 已发布视频作品目录识别与双区沉浸预览、收藏标签和搜索交互、来源侧滑及 LibVLC 单声道转双声道修复。双端正式包的安装、启动与升级记录见 [0.3.1 交付记录](https://github.com/AMindFlow/iPreview/releases/download/v0.3.1/delivery.md)。

## 安装与交付

- macOS 使用 DMG 或应用 ZIP。macOS 26+ 采用原生液态玻璃，15 使用系统材质。
- Windows 使用每用户 EXE 或完整自包含 ZIP。安装、覆盖升级和卸载按 [PLAT-005](../specs/official/platforms.md#plat-005-首版标准安装包)保留本地资料库。Mac 包采用 ad hoc 签名且未公证，Windows 安装器尚无 Authenticode 签名。
- 正式包、最终提交、校验值和实机记录由 [GitHub Releases](https://github.com/AMindFlow/iPreview/releases) 提供。操作参照[版本发布流程](../workflow/release.md)。

## 后续工作

外部样张提供方与获取方式待确认。Windows 包体瘦身在 [#26](https://github.com/AMindFlow/iPreview/issues/26) 独立跟踪。后续需求和已发布版本的验证记录集中在[总体需求 #3](https://github.com/AMindFlow/iPreview/issues/3)。
