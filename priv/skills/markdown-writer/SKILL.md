---
name: markdown-writer
description: Write and format Markdown documents, READMEs, documentation
triggers: [markdown, readme, md, document, write doc, format, table, heading, badge, changelog]
---

## Markdown Writer

### Document structure
```markdown
# Title (H1 — one per document)

Brief description or intro paragraph.

## Section (H2)

### Subsection (H3)

Content with **bold**, *italic*, `inline code`.

- Bullet list
- Another item
  - Nested item

1. Numbered list
2. Second item
```

### Code blocks
````markdown
```elixir
defmodule Example do
  def hello, do: "world"
end
```

```bash
mix deps.get
mix test
```
````

### Tables
```markdown
| Column 1 | Column 2 | Column 3 |
|----------|----------|----------|
| data     | data     | data     |
| data     | data     | data     |
```

### Links & images
```markdown
[Link text](https://example.com)
![Alt text](path/to/image.png)

<!-- Reference style -->
[Link text][ref]
[ref]: https://example.com
```

### Badges (for READMEs)
```markdown
![Build](https://github.com/user/repo/workflows/CI/badge.svg)
[![Hex.pm](https://img.shields.io/hexpm/v/package.svg)](https://hex.pm/packages/package)
```

### Task lists
```markdown
- [x] Completed task
- [ ] Pending task
- [ ] Another pending
```

### Blockquotes & admonitions
```markdown
> Note: This is important information.

> **Warning:** Be careful with this operation.
```

### Rules
- One H1 per document (the title)
- Keep lines under 120 characters where possible
- Use code fences with language identifiers
- Add blank lines between sections
- Write in the same language as the user
