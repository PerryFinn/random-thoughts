# Issue tracker：GitHub

本仓库的 issue 和 spec 存放在 GitHub Issues 中。所有操作使用 `gh` CLI。

## 约定

- **创建 issue**：`gh issue create --title "..." --body "..."`。多行正文使用 heredoc。
- **读取 issue**：`gh issue view <number> --comments`，并使用 `jq` 过滤评论及标签。
- **列出 issue**：`gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`，按需添加 `--label` 和 `--state` 过滤。
- **评论 issue**：`gh issue comment <number> --body "..."`
- **添加或移除标签**：`gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **关闭 issue**：`gh issue close <number> --comment "..."`

通常从 `git remote -v` 推断仓库；在 clone 中运行时，`gh` 会自动使用该仓库。本仓库已配置 GitHub remote，`gh` 可以自动使用该仓库。

## 将 Pull Request 作为 triage 请求入口

**PR 作为请求入口：否。**（如果本仓库将外部 PR 视为 feature request，可将其改为 `yes`；`/triage` 会读取此配置。）

如果改为 `yes`，PR 将使用与 issue 相同的标签和状态，并使用对应的 `gh pr` 命令：

- **读取 PR**：`gh pr view <number> --comments` 和 `gh pr diff <number>`。
- **列出用于 triage 的外部 PR**：`gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments`，只保留 `authorAssociation` 为 `CONTRIBUTOR`、`FIRST_TIME_CONTRIBUTOR` 或 `NONE` 的 PR，排除 `OWNER`、`MEMBER` 和 `COLLABORATOR`。
- **评论、添加或移除标签、关闭**：分别使用 `gh pr comment`、`gh pr edit --add-label` / `--remove-label`、`gh pr close`。

GitHub 的 issue 和 PR 共用编号空间，因此单独出现的 `#42` 可能指 issue 或 PR；需要先运行 `gh pr view 42`，失败后再运行 `gh issue view 42`。

## Wayfinding 操作

供 `/wayfinder` 使用。地图是一个带有子 issue 的 GitHub issue。

- **地图**：创建一个带 `wayfinder:map` 标签的 issue，正文包含 Notes、Decisions-so-far 和 Fog。
- **子 ticket**：创建与地图关联的 GitHub 子 issue，并使用 `wayfinder:<type>` 标签（`research`、`prototype`、`grilling` 或 `task`）。如果当前 GitHub 不支持子 issue，就在地图正文的任务列表中添加子任务，并在子 issue 正文开头写入 `Part of #<map>`。认领后，将 ticket 分配给执行任务的开发者。
- **阻塞关系**：使用 GitHub 原生 issue dependency 作为规范且可见的表示。调用 `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>` 添加关系；其中 `<blocker-db-id>` 是阻塞 issue 的数字 database id（通过 `gh api repos/<owner>/<repo>/issues/<n> --jq .id` 获取），不是 `#number` 或 `node_id`。如果无法使用原生依赖，则在子 issue 正文开头写入 `Blocked by: #<n>, #<n>`。所有阻塞 issue 都关闭后，ticket 才算解除阻塞。
- **前沿查询**：列出地图的未关闭子 issue，排除存在未关闭阻塞项或已有 assignee 的 issue；第一个符合条件的 issue 按地图顺序胜出。阻塞项可通过 `issue_dependencies_summary.blocked_by`，或正文中的 `Blocked by` 行判断。
- **认领**：`gh issue edit <n> --add-assignee @me`。这是会话中的第一次写操作。
- **解决**：先执行 `gh issue comment <n> --body "<answer>"`，再执行 `gh issue close <n>`，最后将 context pointer（gist + link）追加到地图的 Decisions-so-far。
