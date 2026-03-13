---
name: documentation
description: Write and update documentation, README, guides, API docs
triggers: [readme, documentation, docs, document, api doc, guide, changelog, jsdoc, typedoc, exdoc]
---

## Documentation

### README structure
1. **Title & description** — what it does, one paragraph
2. **Quick start** — minimum steps to get running
3. **Usage** — common use cases with examples
4. **Configuration** — env vars, config files
5. **API** — key functions/endpoints
6. **License**

### Guidelines
- Write for someone who's never seen the project
- Include copy-pasteable code examples
- Keep it concise — link to detailed docs for advanced topics
- Update when features change

### Elixir @moduledoc / @doc
```elixir
@moduledoc """
One-line summary.

Detailed description if needed.

## Examples

    iex> MyModule.function(arg)
    expected_result
"""

@doc "Brief function description."
@spec function(type) :: return_type
```

### Changelog format
```markdown
## [1.2.0] - 2026-03-13
### Added
- New feature description

### Fixed
- Bug fix description

### Changed
- Breaking change description
```

### Rules
- Don't write docs for obvious code
- Focus on "why" and "how to use", not "what it does line by line"
- Include practical examples over abstract descriptions
