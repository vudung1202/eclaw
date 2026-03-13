---
name: code-generation
description: Generate code, scaffolding, boilerplate for various languages
triggers: [generate, create, scaffold, boilerplate, new file, implement, write code, coding]
---

## Code Generation

### Process
1. Understand the requirements — ask for clarification if vague.
2. Check existing project patterns before generating (read similar files first).
3. Follow the project's existing conventions: naming, structure, style.
4. Generate minimal, working code — no over-engineering.

### Guidelines
- Match existing code style (indentation, naming conventions, imports)
- Include error handling for external boundaries (user input, API calls, file I/O)
- Don't add unnecessary comments — code should be self-documenting
- Don't add features that weren't requested
- Use the project's existing dependencies, don't introduce new ones

### For Elixir
- Use pattern matching over conditionals
- Use `with` for chaining operations that may fail
- Use behaviours for polymorphism
- Pipe operator for data transformations
- Structs with `@enforce_keys` for required fields

### For TypeScript/JavaScript
- Use strict TypeScript types, avoid `any`
- Prefer `const` over `let`
- Async/await over raw promises
- Destructuring for clean parameter handling

### After generating
- Write the file using `write_file` tool
- Show a brief summary of what was created and why
