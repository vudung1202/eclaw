---
name: code-review
description: Review code for bugs, security issues, and quality improvements
triggers: [review, code review, check code, quality, bug, lint, audit code]
---

## Code Review

### Process
1. Read the file(s) completely before commenting.
2. Understand the context — what the code is trying to do.
3. Check for issues in order of severity.

### Checklist
- **Correctness**: Logic errors, off-by-one, null/nil handling, race conditions
- **Security**: Injection (SQL, XSS, command), auth bypass, secrets in code, unsafe deserialization
- **Performance**: N+1 queries, unnecessary loops, missing indexes, large memory allocation
- **Error handling**: Unhandled exceptions, silent failures, missing validation
- **Concurrency**: Deadlocks, race conditions, shared mutable state
- **Edge cases**: Empty input, boundary values, unicode, large data

### Output format
```
📍 file.ex:42 — 🔴 Critical: SQL injection via string interpolation
   Use parameterized query instead: Repo.query("SELECT * FROM users WHERE id = $1", [id])

📍 file.ex:87 — 🟡 Warning: No error handling for HTTP call
   Wrap in try/rescue or pattern match on {:error, reason}

📍 file.ex:15 — 🔵 Info: Variable `x` could have a more descriptive name
```

### Severity
- 🔴 **Critical** — Must fix. Security vulnerability, data loss risk, crash
- 🟡 **Warning** — Should fix. Potential bug, performance issue, poor error handling
- 🔵 **Info** — Nice to have. Naming, clarity, minor improvements

### Rules
- Be specific — reference exact lines, show the fix
- Don't nitpick style unless asked
- Focus on what matters: correctness > security > performance > style
