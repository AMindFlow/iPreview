# iPreview 项目规则

项目目标、支持平台和技术栈见[项目概览](docs/project/overview.md)。

项目文档用中文，代码、标识符和命令保留原样。

## 开始工作

- 按任务读取相关目录的规则和文档。[文档索引](docs/README.md)列出了主要入口。
- 多 Agent 并行工作时，各用独立工作区/Worktree；无法隔离就顺序执行。
- 新增生产依赖、外部服务、网络调用或遥测前，先获得用户同意。保护凭据和本地媒体。
- 分支、提交和 PR 遵循 [GitHub Flow](docs/workflow/git.md)。

## 审批与验证

- **普通改动**做与改动相称的检查，交付时说明结果和未验证项。
- **实质改动**涉及行为、接口、架构、数据、构建或协作流程。按 [SDD 流程](docs/workflow/sdd.md)先确认需求和验收条件。代理完成客观检查，需要用户判断的事项由用户确认。
- **高风险改动**包括扩大权限、改变凭据或用户数据的访问边界、改写或删除原始媒体、破坏性迁移，以及其他难以撤销的操作。先取得明确授权，写清恢复方案，再按[验证规则](docs/.agent/conventions/validation.md)安排独立检查。

## Code Review Rules

- 审阅当前 PR 提交，按改动范围检查规格、原始媒体、权限边界和数据兼容性。若改了 CI 门禁，检查失败仍会阻止合并的证据。
- Review 正文首个非空行只写 `REVIEW_RESULT: PASS` 或 `REVIEW_RESULT: NEEDS_CHANGES`，使用纯文本。每次审阅只写一个结果，无发现时也写。
- 有阻塞问题或缺少必要证据时，写 `REVIEW_RESULT: NEEDS_CHANGES`，并在下一行说明问题和建议修改。确认审阅完成且无阻塞问题后，才写 `REVIEW_RESULT: PASS`。
