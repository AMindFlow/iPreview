# GitHub Flow

遵循 [GitHub Flow](https://docs.github.com/en/get-started/using-github/github-flow)。`main` 是默认分支，所有改动走 PR，默认 squash 合并。禁止直推或强推 `main`。

- 为可独立审阅和验收的工作包分别建 Issue、远程分支与 PR。PR 链接相应规格编号、前置 PR 与验收证据。可独立审阅的共用契约先拆出，平台与样例任务在契约明确后并行接入。
- 并行开发各用独立 worktree。需要一起验收的强关联改动在 PR 中说明原因和边界。产品发布可汇总多个相关 PR，用候选提交统一构建、自测并请求人工验收，通过后再合入。
- 在本地完成多轮实现、自测和 `codex review`，再集中推送可审阅的候选提交。本地 Codex 审阅使用 `review_model = "gpt-6-astra"`（GPT-6 Astra）。
- Codex 自动审阅触发后逐项记录处理结果。P0 和影响主体功能的意见必须修复并复验；其他意见可附影响和证据交人工决定。进入 Merge Queue 前完成审阅、CI 和候选人工验收，记录其对应提交。
