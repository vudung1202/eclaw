---
name: git-pr
description: Review and manage GitHub Pull Requests using gh CLI
triggers: [pr, pull request, merge request, review pr, merge, gh pr]
---

## Pull Request Management

Use `gh` CLI for all PR operations. Always `cd` to the project first.

### List PRs
```bash
cd /path/to/project && gh pr list
gh pr list --state open|closed|merged|all
gh pr list --author username
gh pr list --label "bug"
gh pr list --search "keyword"
```

### View PR details
```bash
gh pr view <number>
gh pr view <number> --json title,body,author,reviewRequests,statusCheckRollup
gh pr diff <number>
gh pr diff <number> --stat
gh pr checks <number>
```

### Create PR
```bash
gh pr create --title "title" --body "description" --base main
gh pr create --draft
gh pr create --reviewer user1,user2
```

### Review & Merge
```bash
gh pr review <number> --approve
gh pr review <number> --request-changes --body "feedback"
gh pr merge <number> --squash
gh pr merge <number> --rebase
```

### Rules
- Always show PR number, title, author, and status
- Combine commands: `gh pr list && echo "---" && gh pr view 123`
- For diffs, use `--stat` first for overview, then full diff if needed
