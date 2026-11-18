# 当前状态

iPreview 0.1.0 的图片与基础视频桌面功能已获用户确认作为一期交付。最新功能包含 [PR #48](https://github.com/AMindFlow/iPreview/pull/48)、[#49](https://github.com/AMindFlow/iPreview/pull/49)、[#50](https://github.com/AMindFlow/iPreview/pull/50)的侧栏与玻璃控件反馈、预览退出选择、展示快捷键及 Windows 布局对齐，不再停留于最早的首版切片。

[一期验收登记册](releases/0.1.0.md)列出全部已交付及后续细化规格、PR 和验证边界。[原始需求映射](requirements.md#原始需求逐项对应)覆盖最初文档；[未完成清单](backlog.md)独立记录所有后续目标。[路线图](roadmap.md)决定排期依赖，[一期分工与 DAG](phase-1-collaboration.md)供其他 Agent 审阅协作方式。

## 一期交付

- Mac ARM64：macOS15+，提供 DMG 和 `.app` ZIP。macOS26+ 采用原生液态玻璃，15 使用系统材质。
- Windows11 x64：原生 WinUI3，提供每用户 EXE 安装器和完整自包含 ZIP，无须联网安装 .NET／Windows App SDK。与 Mac 对齐层级、搜索、合集与预览行为，保留 Windows 原生窗框。
- 双端已安装最新版本并做 Computer Use 复验，原索引和合集可恢复。原始媒体日常只读；真实重命名仅按明确的 [LIB-011](../specs/official/library.md#lib-011-重命名真实目录和媒体)执行。
- 最终版本物料集中在版本子目录：包、样例、提交／哈希、验收结果、主页截图和清理清单。最新提交和下载见 [v0.1.0 Release](https://github.com/AMindFlow/iPreview/releases/tag/v0.1.0)，不把阶段临时目录作为长期交付入口。
- 标准安装器见 [PLAT-005](../specs/official/platforms.md#plat-005-首版标准安装包)。当前没有发行签名证书，Mac 为 ad hoc 签名且未公证，Windows 安装器未做 Authenticode 签名。

## 未完成与验证边界

[PR #27](https://github.com/AMindFlow/iPreview/pull/27)的 Windows WinUI 组件包瘦身仍待干净 Windows11 x64 离线验收，保持草稿、不计入一期发布。音频、漫画、视频作品组织与影碟图册、多工作区、旧库迁移、元信息、标签／封面等未完成内容均在[未完成清单](backlog.md)。

macOS15 已通过原生启动 CI，最终视觉未逐项人工复核；辅助功能／透明效果未做全矩阵人工切换，扬声器输出未完整核验。实际证据不扩大为未执行过的验证。

数据结构与迁移由[共享 SQLite 契约](../../shared/README.md)定义。已完成工作通过 PR／Merge Queue 进入 main；未验收的独立候选保留自己的追踪，不为文档收尾强行合入。
