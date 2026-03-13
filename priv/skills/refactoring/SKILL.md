---
name: refactoring
description: Refactor code - extract, rename, simplify, restructure
triggers: [refactor, clean up, simplify, extract, rename, restructure, dry, duplication, technical debt, tech debt]
---

## Refactoring

### Process
1. **Read first** — understand what the code does before changing it
2. **Check tests** — ensure tests exist before refactoring. Run them.
3. **Small steps** — one change at a time, verify after each
4. **Preserve behavior** — refactoring must not change what the code does

### Common refactorings
- **Extract function** — long function → smaller named functions
- **Extract module** — large module → split by responsibility
- **Rename** — unclear names → descriptive names
- **Remove duplication** — repeated code → shared function
- **Simplify conditionals** — nested if/else → pattern matching, guard clauses, `with`
- **Replace magic values** — hardcoded numbers/strings → named constants

### Elixir-specific
```elixir
# Before: nested case
case foo() do
  {:ok, a} ->
    case bar(a) do
      {:ok, b} -> {:ok, b}
      {:error, e} -> {:error, e}
    end
  {:error, e} -> {:error, e}
end

# After: with
with {:ok, a} <- foo(),
     {:ok, b} <- bar(a) do
  {:ok, b}
end
```

### Rules
- Don't refactor and add features at the same time
- Don't refactor without tests
- Don't over-abstract — 3 similar lines is fine, premature abstraction is worse
- Run tests after every change
