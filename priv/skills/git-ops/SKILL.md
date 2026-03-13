---
name: git-ops
description: Git operations - branches, commits, diffs, logs, stash
triggers: [git, branch, commit, diff, log, merge, rebase, stash, checkout, cherry-pick, tag]
---

## Git Operations

Always `cd` to the project directory first. Combine commands in ONE bash call.

### Status & Info
```bash
git status && git log --oneline -10
git branch -a
git remote -v
git stash list
```

### Branching
```bash
git checkout -b feature/name
git checkout main
git branch -d old-branch
```

### Commits & History
```bash
git log --oneline -20
git log --oneline --graph --all -20
git log --author="name" --oneline -10
git show <commit-hash>
git diff HEAD~3..HEAD
```

### Diffs
```bash
git diff                          # unstaged changes
git diff --staged                 # staged changes
git diff branch1..branch2        # between branches
git diff --stat branch1..branch2 # summary only
```

### Stash
```bash
git stash
git stash list
git stash pop
git stash show -p stash@{0}
```

### FORBIDDEN — never run these:
- `git init` (creates unwanted repos)
- `git push --force` (destroys remote history)
- `git reset --hard` (loses uncommitted work)
- `git clean -fd` (deletes untracked files permanently)
