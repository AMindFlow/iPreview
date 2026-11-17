# iPreview 完整需求

iPreview 重启并升级 picosmic。产品承接本地图片库、Quick Look 式键盘预览、虚拟专辑和多工作区，逐步支持旧版全部图片格式及常见视频、音频格式。[首版 Issue #1](https://github.com/AMindFlow/iPreview/issues/1)记录首个交付切片，[总体需求 #3](https://github.com/AMindFlow/iPreview/issues/3)追踪完整范围。

所有提出的需求在排期前登记。按下表查阅生效规格和已登记的后续需求，按[路线图](roadmap.md)查阅交付顺序、依赖及待决定的事项。

| 维度 | 生效规格 | 已登记的后续需求 |
| --- | --- | --- |
| 本地媒体库 | [LIB-001、LIB-002、LIB-009、LIB-010、LIB-011、LIB-012](../specs/official/library.md) | [旧版图库管理、多工作区、旧库迁移、两种视频作品、音频组织与待定旧版文件操作](../specs/spike/library.md) |
| 键盘预览 | [PRE-001、PRE-007、PRE-008、PRE-009](../specs/official/preview.md) | [普通图片效果、漫画双页、视频影碟与图册、音频封面与 CD 机、常见视频格式](../specs/spike/preview.md) |
| 专辑浏览 | [图片点击响应](../specs/official/browsing.md#brw-001-图片选中响应)、[图标、列表与画廊](../specs/official/browsing.md#brw-002-图标列表和画廊视图) | |
| 搜索 | [SRCH-001、SRCH-002](../specs/official/search.md) | [旧版分类结果及标签搜索](../specs/spike/search.md) |
| 专辑组织 | [ALB-001、ALB-004、ALB-005、ALB-006](../specs/official/virtual-albums.md) | [标签、收藏、评分、封面、Windows 拖动重排与删除](../specs/spike/virtual-albums.md) |
| 媒体元信息 | | [从文件提取及修改后写回](../specs/spike/metadata.md) |
| 应用视觉 | [UI-001 应用图标、UI-002 虚拟专辑选片器、UI-003 macOS 原生液态玻璃、UI-004 Windows 图库材质与来源图标](../specs/official/appearance.md) | |
| 平台与分发 | [平台与技术栈](overview.md) | [iOS、旧版浏览器与局域网入口、桌面安装升级](../specs/spike/platforms.md) |

## 设计要求

- 界面简洁、现代，以原生侧栏、媒体网格与沉浸式预览承载首版选定的设计语言。视觉参考依次为 macOS 26+ 液态玻璃、Google Stitch 当期风格、用户提供的本地 `clarity-frontend-reference`。保留旧版浅色、深色和跟随系统主题的选择与恢复需求。
- 美术探索优先由 agy 子代理完成，额度用于设计。优先采用 Hydrogen High 和 Flex，响应速度低于 5 tok/s 时切到 Standard。
- 旧版没有的页面或流程，在实施前用 ImageGen 出至少两套示例，采用一套并保留备选供审阅。音频设计以及其他会实质影响产品或访问边界的决定按 [SDD 流程](../workflow/sdd.md)确认。

## 交付要求

- 可并行工作使用独立 worktree。按 [GitHub Flow](../workflow/git.md)拆分、审阅和合入，处理 Codex 自动审阅意见。规划各工作包依赖，每阶段交付附任务 DAG。
- 首版目标包为 Mac ARM64 `.app` ZIP 与 Windows 11 x64 自包含 ZIP。跨平台产品交付基于同一最终提交，在本机 Apple Silicon Mac 与 Windows App 可连接的 Windows 11 实机用同一套样例验收。具备桌面访问时用 Computer Use 自行完成界面操作。iOS 阶段验收见 [PLAT-001](../specs/spike/platforms.md#plat-001-ios-原生体验)。
- 交付随包附样例、步骤和结果、提交 SHA、PR 和构建产物链接。首版验收覆盖重启恢复、搜索、图片与视频预览、虚拟专辑、损坏文件、离线及恢复，核对源文件路径、内容和修改时间。见[验收步骤](acceptance.md)。

## 旧版追溯

旧版基线为本地 picosmic 恢复仓库提交 `cde3952`。下列路径相对于旧仓库，用于追溯已有行为和未完成验证的旧规格。

| 范围 | 旧版路径 |
| --- | --- |
| 图片格式、创作者入口与预览 | `src/server/utils.ts`、`src/web/app.tsx`、`test/e2e/library-browsing.spec.ts`、`docs/specs/official/library-browsing/spec.md` |
| 专辑组织、搜索、备份 | `docs/specs/official/catalog-organization/spec.md` |
| 源文件操作及局域网 | `docs/specs/official/safe-file-operations-and-lan/spec.md` |
| 多工作区、安装及旧数据 | `docs/specs/spike/desktop-distribution/spec.md`、`docs/specs/spike/desktop-usability-followups/spec.md`、`docs/project/current-state.md` |
