---
name: project-explore
description: Explore and understand project structure, codebase, architecture
triggers: [project, structure, explore, codebase, architecture, what is, how does, explain project, overview]
---

## Project Exploration

### Quick overview (ONE bash call)
```bash
cd /path/to/project && echo "=== FILES ===" && find . -type f \( -name "*.ex" -o -name "*.exs" -o -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.go" -o -name "*.rs" \) | grep -v node_modules | grep -v _build | grep -v deps | grep -v .git | head -40 && echo "=== README ===" && head -60 README.md 2>/dev/null
```

### Detect stack
| File | Stack |
|------|-------|
| `mix.exs` | Elixir/Phoenix |
| `package.json` | Node.js |
| `Cargo.toml` | Rust |
| `go.mod` | Go |
| `requirements.txt` / `pyproject.toml` | Python |
| `Gemfile` | Ruby |
| `docker-compose.yml` | Docker |

### Key files to read (by priority)
1. `README.md` or `CLAUDE.md` — documentation
2. Config file (`mix.exs`, `package.json`, `Cargo.toml`) — deps & settings
3. Entry point (`lib/app/application.ex`, `src/index.ts`, `main.go`)
4. Router/routes (`router.ex`, `routes/`, `urls.py`)

### Output format
Provide a concise summary:
- **Stack**: language, framework, key dependencies
- **Structure**: main directories and their purpose
- **Entry points**: where the app starts
- **Key modules**: most important files/modules
