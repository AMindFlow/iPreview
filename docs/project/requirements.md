# iPreview 完整需求

iPreview 重启并升级 picosmic。需求总范围包括旧版图库工作流、图片、常见视频和音频、多工作区、旧库迁移与媒体元信息。0.1.0 是其中已验收的图片／基础视频桌面交付，不代表全部产品目标完成。

- [原始需求快照](requirements-original.md)保存用户提供的最初文档；其中路径与旧产品名称属于原文。下表逐项映射原始范围。
- [一期验收登记册](releases/0.1.0.md)登记已交付功能、后续细化及 PR，实际行为由 `official/` 规格定义。
- [未完成需求](backlog.md)单独登记部分完成、待实施、待决策和待验收项，使用原规格编号追踪。
- [路线图](roadmap.md)记录先后依赖；[分工与 DAG](phase-1-collaboration.md)记录一期实际工作包。[总体 Issue #3](https://github.com/AMindFlow/iPreview/issues/3)追踪整个产品，[一期收尾 #51](https://github.com/AMindFlow/iPreview/issues/51)追踪本轮归档。

## 原始需求逐项对应

下表的 `ORIG-*` 是原文追溯行号；功能规范继续使用 `LIB/PRE/ALB/SRCH/META/UI/PLAT/BRW` 编号。已完成仅针对表中写明的范围。

| 原文追溯 | 最初需求 | 一期状态与规格去向 |
| --- | --- | --- |
| ORIG-01 | 重启 picosmic，承接原本图库、键盘预览和跨目录虚拟专辑 | 核心已交付：[LIB-001–002](../specs/official/library.md)、[PRE-001、007–011](../specs/official/preview.md)、[ALB-001、004–006](../specs/official/virtual-albums.md)。旧版其余工作流逐项保留在[未完成清单](backlog.md)。产品用语已统一为「合集」。 |
| ORIG-02 | 旧版所有图片类型 | JPEG/JPG、PNG、WebP、GIF 及 macOS HEIC 已交付；Windows HEIC 依赖系统解码器。[PRE-001](../specs/official/preview.md#pre-001-图片与视频预览)。 |
| ORIG-03 | 常见视频格式 | 部分完成：系统框架播放 H.264/AAC MP4、MOV；额外容器／编码的实际缺口及成熟播放底座扩展见 [PRE-006](../specs/spike/preview.md#pre-006-常见视频格式扩展)。 |
| ORIG-04 | 常见音频格式 | 待设计、审阅与实施：[LIB-007](../specs/spike/library.md#lib-007-音频组织)。 |
| ORIG-05 | creator → album 自动识别 | 已交付：[LIB-001](../specs/official/library.md#lib-001-目录导入与扫描)。 |
| ORIG-06 | multi-creators → creator → album 自动识别 | 已交付，先选择创作者、再进入其专辑：[LIB-009、010](../specs/official/library.md)。 |
| ORIG-07 | 视频完整作品结构：主视频、官方样张、多个带封面写真集 | 待实施：[LIB-006](../specs/spike/library.md#lib-006-两种视频作品结构)。官方样张的外部提供方与获取方式待确认。 |
| ORIG-08 | 视频简化作品结构：根目录视频及样张、写真集图片平铺 | 待实施，同属 [LIB-006](../specs/spike/library.md#lib-006-两种视频作品结构)。 |
| ORIG-09 | 音频管理体系由代理设计，用户审阅后做 | 已登记，后置且保留审阅条件：[LIB-007](../specs/spike/library.md#lib-007-音频组织)、[PRE-005](../specs/spike/preview.md#pre-005-音频专辑封面与-cd-机)。 |
| ORIG-10 | Space、方向键快速浏览媒体，参考旧版行为 | 已交付并按后续确认细化：[PRE-007、008](../specs/official/preview.md)、[LIB-010](../specs/official/library.md#lib-010-创作者和专辑层级键盘浏览)。 |
| ORIG-11 | 各级目录名和文件名模糊搜索 | 已交付，含拼音、首字母和拼写容错：[SRCH-001](../specs/official/search.md#srch-001-目录名与文件名)。 |
| ORIG-12 | 精确／模糊及文件／目录搜索模式 | 已交付，最终使用居中搜索、快捷键与 `@` 后空格：[SRCH-001、002](../specs/official/search.md)。旧版标签搜索另见 [SRCH-003](../specs/spike/search.md#srch-003-旧版分类结果与标签搜索)。 |
| ORIG-13 | 从媒体提取清晰度、作者等元信息 | 待实施：[META-001](../specs/spike/metadata.md#meta-001-提取和展示专辑文件元信息)。一期列表中的大小、修改时间及种类不代表此项完成。 |
| ORIG-14 | 应用内修改元信息并反映到实际文件 | 待字段、格式和恢复方案确认：[META-002](../specs/spike/metadata.md#meta-002-修改并写回实际文件)。 |
| ORIG-15 | 图片主显、自适应、四向相邻图层叠弱化，其余区域弱化 | 已交付当前图片预览；后续确认以毛玻璃遮挡下层、无黑色遮罩。[PRE-001、009、010](../specs/official/preview.md)。旧版原始尺寸、首尾跳转和滑动补齐见 [PRE-002](../specs/spike/preview.md#pre-002-常规图片预览与旧版兼容)。 |
| ORIG-16 | 漫画左右双页、即时调整首页单双页、仿真翻页 | 待实施：[PRE-003](../specs/spike/preview.md#pre-003-漫画双页翻页)。 |
| ORIG-17 | 视频作品以影碟和图册展示、选择进入、Esc 逐层退出 | 待实施：[PRE-004](../specs/spike/preview.md#pre-004-视频作品的影碟与图册预览)。原文 Enter 进入已被后续 Space 进入口径替代，Enter 用于真实重命名或视频预览锁定。 |
| ORIG-18 | 音频封面与 CD 机模拟，其他由代理设计 | 待审阅与实施：[PRE-005](../specs/spike/preview.md#pre-005-音频专辑封面与-cd-机)。 |
| ORIG-19 | 多工作区，分别保存文件夹与专辑管理数据 | 待实施：[LIB-004](../specs/spike/library.md#lib-004-多工作区)。一期只有默认本地库，测试用数据目录不算工作区产品功能。 |
| ORIG-20 | 跨 macOS／Windows 原生可用并实机测试 | 一期桌面已交付，macOS 15 启动有 CI 验证；实际视觉和辅助功能未全矩阵人工复验，见[一期登记册](releases/0.1.0.md)。 |
| ORIG-21 | 视觉依次参考液态玻璃、Stitch、本地前端参考 | 当前界面已按后续参考细化：[UI-001–006](../specs/official/appearance.md)。macOS 26+ 原生玻璃，macOS 15 系统材质；Windows 以原生窗框和材质对齐布局。 |
| ORIG-22 | 美术先用 agy，Hydrogen High／Flex，低速再 Standard | 持续设计约束，见下文；不把全部实现交给 agy。 |
| ORIG-23 | 新增流程先 ImageGen 两套，先采用一套保留备选 | 持续设计约束；选片器采用用户选定的底部胶片条，备选随版本设计资料保存。 |
| ORIG-24 | 先 roadmap、分期 specs，仅重大取舍请求决定 | [路线图](roadmap.md)、分维度 `official/spike` 与 [SDD 流程](../workflow/sdd.md)持续执行。 |
| ORIG-25 | 多 Agent 并行、交付任务 DAG | 已记录[一期分工与任务 DAG](phase-1-collaboration.md)，后续仍按独立 worktree／可独立验收 PR 拆分。 |
| ORIG-26 | GitHub Flow、禁止直推 main、关注 Codex Review | 已采用 PR、独立审阅与 Merge Queue；见[工作流](../workflow/git.md)及一期 PR 台账。 |

## 设计与交付约束

- 界面简洁、现代，保留原生侧栏、媒体网格与沉浸预览。参考优先级沿用原文。旧版浅色／深色／跟随系统的显式设置尚待 [UI-007](../specs/spike/appearance.md#ui-007-主题选择与恢复)，已有跟随系统不等于该设置完成。
- 美术探索优先由 agy 做设计，使用 Hydrogen High／Flex，响应低于 5 tok/s 时可切 Standard。旧版没有的页面流程先出至少两套 ImageGen 方案，保留备选供审阅；音频设计和重大权限／数据决定先由用户确认。
- 一期交付形式为 Mac ARM64 DMG 与 `.app` ZIP、Windows 11 x64 自包含 EXE 安装器与 ZIP。安装边界见 [PLAT-005](../specs/official/platforms.md#plat-005-首版标准安装包)。不需要安装器的用户仍可使用完整 ZIP。
- 同一最终源码构建双端，附提交 SHA、SHA-256、合成样例、实际验收、主页截图及 DAG。跨平台实机验收及源文件只读检查见[验收步骤](acceptance.md)；通过 Computer Use 自行操作。版本物料以版本子目录集中保存，过时物料移回收站且不清空。

## 旧版追溯

旧版基线为 picosmic 恢复仓库提交 `cde3952`。以下为旧仓库相对路径，支持后续补齐旧版需求时核对。

| 范围 | 旧版路径 |
| --- | --- |
| 图片格式、创作者入口与预览 | `src/server/utils.ts`、`src/web/app.tsx`、`test/e2e/library-browsing.spec.ts`、`docs/specs/official/library-browsing/spec.md` |
| 专辑组织、搜索、备份 | `docs/specs/official/catalog-organization/spec.md` |
| 源文件操作及局域网 | `docs/specs/official/safe-file-operations-and-lan/spec.md` |
| 多工作区、安装及旧数据 | `docs/specs/spike/desktop-distribution/spec.md`、`docs/specs/spike/desktop-usability-followups/spec.md`、`docs/project/current-state.md` |
