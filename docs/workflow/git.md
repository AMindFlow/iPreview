# GitHub Flow

遵循 [GitHub Flow](https://docs.github.com/en/get-started/using-github/github-flow)。`main` 是默认分支，所有改动走 PR，默认 squash 合并。禁止直推或强推 `main`。

- 为可独立审阅和验收的工作包分别建 Issue、远程分支与 PR。PR 链接相应规格编号、前置 PR 与验收证据。可独立审阅的共用契约先拆出，平台与样例任务在契约明确后并行接入。
- 并行开发各用独立 worktree。需要一起验收的强关联改动在 PR 中说明原因和边界。产品发布可以汇总多个已合入的 PR，随最终提交统一构建和实机验收。
- 查看 Codex 自动审阅，处理阻塞意见并解决审阅线程，完成与改动相称的检查后进入 Merge Queue。发布证据引用当次验收的提交和产物。
