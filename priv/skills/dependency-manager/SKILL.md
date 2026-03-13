---
name: dependency-manager
description: Manage project dependencies, packages, versions
triggers: [dependency, package, library, hex, npm, pip, gem, cargo, mix deps, version, upgrade, outdated, vulnerability]
---

## Dependency Management

### Elixir (Mix + Hex)
```bash
# Add dependency — edit mix.exs, then:
mix deps.get

# List dependencies
mix deps

# Update specific
mix deps.update jason

# Update all
mix deps.update --all

# Check outdated
mix hex.outdated

# Dependency tree
mix deps.tree

# Clean
mix deps.clean --all
mix deps.get
```

```elixir
# In mix.exs
defp deps do
  [
    {:phoenix, "~> 1.7"},        # compatible with 1.7.x
    {:jason, "~> 1.4"},          # compatible with 1.4.x
    {:ex_doc, "~> 0.34", only: :dev, runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test]},
  ]
end
```

### Node.js (npm/yarn/pnpm)
```bash
# Install
npm install                       # from package.json
npm install package-name          # add dependency
npm install -D package-name       # dev dependency

# Update
npm outdated                      # check outdated
npm update                        # update within semver
npx npm-check-updates -u          # update package.json to latest

# Audit
npm audit                         # check vulnerabilities
npm audit fix                     # auto-fix

# Clean
rm -rf node_modules && npm install
```

### Python (pip/poetry)
```bash
# pip
pip install package-name
pip install -r requirements.txt
pip freeze > requirements.txt
pip list --outdated

# poetry
poetry add package-name
poetry update
poetry show --outdated
poetry lock
```

### Version constraints
```
~> 1.4      # >= 1.4.0 and < 2.0.0 (Elixir)
~> 1.4.2    # >= 1.4.2 and < 1.5.0 (Elixir)
^1.4.0      # >= 1.4.0 and < 2.0.0 (npm)
~1.4.0      # >= 1.4.0 and < 1.5.0 (npm)
>=1.4,<2.0  # explicit range (pip)
```

### Rules
- Always pin major versions (`~>` or `^`)
- Run tests after updating dependencies
- Check changelogs before major upgrades
- Use `only: :dev` / `only: :test` for non-production deps
- Audit for security vulnerabilities regularly
