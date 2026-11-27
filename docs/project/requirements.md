# iPreview 完整需求

iPreview 重启并升级 picosmic。需求总范围包括旧版图库工作流、图片、常见视频和音频、多工作区、旧库迁移与媒体元信息。桌面交付范围分别记录在 [0.1.0](releases/0.1.0.md) 和 [0.2.0](releases/0.2.0.md)。[0.3.0 版本登记](releases/0.3.0.md)汇总 [#75](https://github.com/AMindFlow/iPreview/issues/75) 与用户指定的首版延续需求。

- [原始需求快照](requirements-original.md)保存用户提供的最初文档；其中路径与旧产品名称属于原文。下表逐项映射原始范围。
- [一期验收登记册](releases/0.1.0.md)登记已交付功能、后续细化及 PR，实际行为由 `official/` 规格定义。
- [未完成需求](backlog.md)单独登记部分完成、待实施、待决策和待验收项，使用原规格编号追踪。
- [路线图](roadmap.md)记录先后依赖。[一期分工](phase-1-collaboration.md)和[二期分工](phase-2-collaboration.md)保留实际工作包及 DAG。[总体 Issue #3](https://github.com/AMindFlow/iPreview/issues/3)追踪整个产品。
- [0.2.0 发布与验收](releases/0.2.0.md)记录交付范围和剩余工作。预览体验 [#57](https://github.com/AMindFlow/iPreview/issues/57) 已随 0.2.0 交付，包括退出选择、复制反馈和 PRE-008 连续切图保留画面。

## 原始需求逐项对应

下表的 `ORIG-*` 是原文追溯编号；功能规范继续使用 `LIB/PRE/ALB/SRCH/META/UI/PLAT/BRW` 编号。已完成仅针对表中写明的范围。

| 原文追溯 | 最初需求 | 交付状态与规格去向 |
| --- | --- | --- |
| ORIG-01 | 重启 picosmic，承接原本图库、键盘预览和跨目录虚拟专辑 | 0.1.0 交付[图库](../specs/official/library.md)、[键盘预览](../specs/official/preview.md)和[跨目录合集](../specs/official/virtual-albums.md)。0.2.0 交付合集删除、主题选择与恢复。0.3.0 纳入来源操作、媒体排序与来源专辑组织，详见[本期工作包](releases/0.3.0.md#工作包与合入状态)。 |
| ORIG-02 | 旧版所有图片类型 | JPEG/JPG、PNG、WebP、GIF 及 macOS HEIC 已交付；Windows HEIC 依赖系统解码器。[PRE-001](../specs/official/preview.md#pre-001-图片与视频预览)。 |
| ORIG-03 | 常见视频格式 | 0.1.0 以系统框架播放 H.264/AAC MP4、MOV。0.3.0 扩展 MPEG-TS、MKV、WebM、AVI，后三种在系统播放失败时使用本地 LibVLC 回退。[PRE-006 交付与验收](releases/0.3.0.md#工作包与合入状态) |
| ORIG-04 | 常见音频格式 | 待设计、审阅与实施：[LIB-007](../specs/spike/library.md#lib-007-音频组织)。 |
| ORIG-05 | creator → album 自动识别 | 已交付：[LIB-001](../specs/official/library.md#lib-001-目录导入与扫描)。 |
| ORIG-06 | multi-creators → creator → album 自动识别 | 已交付，先选择创作者、再进入其专辑：[LIB-009、010](../specs/official/library.md)。 |
| ORIG-07 | 视频完整作品结构：主视频、官方样张、多个带封面写真集 | 双端按层级识别本地完整作品，样张和专用封面可省略。外部样张来源待确认，见 [LIB-006](../specs/official/library.md#lib-006-两种视频作品结构)。 |
| ORIG-08 | 视频简化作品结构：根目录视频及样张、写真集图片平铺 | [LIB-006](../specs/official/library.md#lib-006-两种视频作品结构)双端识别根目录一个视频及任意命名的直属图片目录，样张可省略。 |
| ORIG-09 | 音频管理体系由代理设计，用户审阅后做 | 已登记，后置且保留审阅条件：[LIB-007](../specs/spike/library.md#lib-007-音频组织)、[PRE-005](../specs/spike/preview.md#pre-005-音频专辑封面与-cd-机)。 |
| ORIG-10 | Space、方向键快速浏览媒体，参考旧版行为 | 键盘预览见 [PRE-007、008](../specs/official/preview.md)及 [LIB-010](../specs/official/library.md#lib-010-创作者和专辑层级键盘浏览)。0.2.0 同步退出选择、改善列表滚动，并在连续切图时保留画面。见 [PR #67](https://github.com/AMindFlow/iPreview/pull/67)。 |
| ORIG-11 | 各级目录名和文件名模糊搜索 | 已交付，含拼音、首字母和拼写容错：[SRCH-001](../specs/official/search.md#srch-001-目录名与文件名)。 |
| ORIG-12 | 精确／模糊及文件／目录搜索模式 | 0.1.0 交付精确、模糊与文件、目录筛选。0.2.0 增加创作者、专辑类别标记。0.3.0 增加结果分组、标签过滤与 `#` 联想，保留原有作用域与定位。[分类与标签搜索 PR #78](https://github.com/AMindFlow/iPreview/pull/78) |
| ORIG-13 | 从媒体提取清晰度、作者等元信息 | 待实施：[META-001](../specs/spike/metadata.md#meta-001-提取和展示专辑文件元信息)。一期列表中的大小、修改时间及种类不代表此项完成。 |
| ORIG-14 | 应用内修改元信息并反映到实际文件 | 待字段、格式和恢复方案确认：[META-002](../specs/spike/metadata.md#meta-002-修改并写回实际文件)。 |
| ORIG-15 | 图片主显、自适应、四向相邻图层叠弱化，其余区域弱化 | 已交付当前图片预览；后续确认以毛玻璃遮挡下层、无黑色遮罩。[PRE-001、009、010](../specs/official/preview.md)。 |
| ORIG-16 | 漫画左右双页、即时调整首页单双页、仿真翻页 | 待实施：[PRE-003](../specs/spike/preview.md#pre-003-漫画双页翻页)。 |
| ORIG-17 | 视频作品以影碟和图册展示、选择进入、Esc 逐层退出 | 双端用玻璃录像带与层叠图册展示专辑，按 Space 进入双区，Tab 在播放和翻图间切换。详见 [PRE-004](../specs/official/preview.md#pre-004-视频作品的沉浸模式)。原文 Enter 进入已被后续 Space 进入口径替代，Enter 用于真实重命名或视频预览锁定。 |
| ORIG-18 | 音频封面与 CD 机模拟，其他由代理设计 | 待审阅与实施：[PRE-005](../specs/spike/preview.md#pre-005-音频专辑封面与-cd-机)。 |
| ORIG-19 | 多工作区，分别保存文件夹与专辑管理数据 | 待实施：[LIB-004](../specs/spike/library.md#lib-004-多工作区)。一期只有默认本地库，测试用数据目录不算工作区产品功能。 |
| ORIG-20 | 跨 macOS／Windows 原生可用并实机测试 | 实机证据按 [0.1.0](releases/0.1.0.md)、[0.2.0](releases/0.2.0.md) 与 [0.3.0](releases/0.3.0.md) 登记。构建包含 macOS 15 启动 CI。正式双端验收结果随本版归档。 |
| ORIG-21 | 视觉依次参考液态玻璃、Stitch、本地前端参考 | 两端原生界面及主题选择见 [UI-001–007](../specs/official/appearance.md)。macOS 26+ 采用原生玻璃，macOS 15 使用系统材质。Windows 使用原生窗框和材质。 |
| ORIG-22 | 美术先用 agy，Hydrogen High／Flex，低速再 Standard | 持续设计约束，见下文；不把全部实现交给 agy。 |
| ORIG-23 | 新增流程先 ImageGen 两套，先采用一套保留备选 | 持续设计约束；选片器采用用户选定的底部胶片条，备选随版本设计资料保存。 |
| ORIG-24 | 先 roadmap、分期 specs，仅重大取舍请求决定 | [路线图](roadmap.md)、分维度 `official/spike` 与 [SDD 流程](../workflow/sdd.md)持续执行。 |
| ORIG-25 | 多 Agent 并行、交付任务 DAG | 按独立 worktree 与可单独验收的 PR 拆分，见[一期分工](phase-1-collaboration.md)、[二期分工](phase-2-collaboration.md)与[0.3.0 分工及依赖](releases/0.3.0.md#分工与依赖)。 |
| ORIG-26 | GitHub Flow、禁止直推 main、关注 Codex Review | 已采用 PR、独立审阅与 Merge Queue；见[工作流](../workflow/git.md)及一期 PR 台账。 |

## 设计与交付约束

- 界面简洁、现代，保留原生侧栏、媒体网格与沉浸预览。参考优先级沿用原文。浅色／深色／跟随系统的选择与恢复见 [UI-007](../specs/official/appearance.md#ui-007-主题选择与恢复)。
- 美术探索优先由 agy 做设计，使用 Hydrogen High／Flex，响应低于 5 tok/s 时可切 Standard。旧版没有的页面流程先出至少两套 ImageGen 方案，保留备选供审阅；音频设计和重大权限／数据决定先由用户确认。
- 一期交付形式为 Mac ARM64 DMG 与 `.app` ZIP、Windows 11 x64 自包含 EXE 安装器与 ZIP。安装边界见 [PLAT-005](../specs/official/platforms.md#plat-005-首版标准安装包)。不需要安装器的用户仍可使用完整 ZIP。
- 双端从同一最终源码构建，记录提交 SHA、产物 SHA-256、合成样例、实际验收、首页截图和 DAG。实机与源文件只读检查见[验收步骤](acceptance.md)。版本物料和获授权的旧资料库处理见[版本发布流程](../workflow/release.md)。

## 旧版追溯

旧版基线为 picosmic 恢复仓库提交 `cde3952`。以下为旧仓库相对路径，支持后续补齐旧版需求时核对。

| 范围 | 旧版路径 |
| --- | --- |
| 图片格式、创作者入口与预览 | `src/server/utils.ts`、`src/web/app.tsx`、`test/e2e/library-browsing.spec.ts`、`docs/specs/official/library-browsing/spec.md` |
| 专辑组织、搜索、备份 | `docs/specs/official/catalog-organization/spec.md` |
| 源文件操作及局域网 | `docs/specs/official/safe-file-operations-and-lan/spec.md` |
| 多工作区、安装及旧数据 | `docs/specs/spike/desktop-distribution/spec.md`、`docs/specs/spike/desktop-usability-followups/spec.md`、`docs/project/current-state.md` |
