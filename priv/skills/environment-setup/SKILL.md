---
name: environment-setup
description: Set up development environments, install tools, configure systems
triggers: [setup, install, configure, environment, env, dotenv, asdf, mise, nvm, pyenv, docker, compose, devcontainer]
---

## Environment Setup

### Version managers
```bash
# asdf (universal)
asdf plugin add elixir
asdf plugin add erlang
asdf plugin add nodejs
asdf install elixir 1.18.1
asdf global elixir 1.18.1
asdf local elixir 1.18.1          # per-project (.tool-versions)

# mise (modern alternative to asdf)
mise install elixir@1.18
mise use elixir@1.18               # sets in .mise.toml

# nvm (Node.js)
nvm install 22
nvm use 22
nvm alias default 22
```

### Environment variables
```bash
# .env file (don't commit!)
DATABASE_URL=postgres://localhost/myapp_dev
SECRET_KEY_BASE=supersecret
TELEGRAM_BOT_TOKEN=123:ABC

# Load in shell
export $(grep -v '^#' .env | xargs)
source .env                        # if using export in .env

# direnv (auto-load per directory)
echo 'dotenv' > .envrc
direnv allow
```

### Elixir project setup
```bash
# New project
mix new my_app
mix phx.new my_app                 # Phoenix

# Existing project
mix deps.get
mix ecto.setup                     # create + migrate + seed
mix phx.server                     # start Phoenix

# Database
mix ecto.create
mix ecto.migrate
mix ecto.reset                     # drop + create + migrate
```

### Docker
```bash
# Start services
docker compose up -d

# Common services
docker compose up -d postgres redis

# Check status
docker compose ps
docker compose logs -f service_name

# Clean
docker compose down
docker compose down -v             # remove volumes too
```

### macOS essentials
```bash
# Homebrew
brew install elixir erlang node postgres redis

# Xcode CLI tools
xcode-select --install
```

### Checklist for new project
1. Clone repo
2. Check `.tool-versions` or `.mise.toml` — install correct runtime versions
3. Copy `.env.example` to `.env` — fill in secrets
4. Install dependencies (`mix deps.get`, `npm install`)
5. Setup database (`mix ecto.setup`)
6. Run tests (`mix test`)
7. Start server (`mix phx.server` or `iex -S mix`)

### Rules
- Never commit `.env` files — add to `.gitignore`
- Use `.env.example` with placeholder values for documentation
- Pin runtime versions in `.tool-versions` or `.mise.toml`
- Document setup steps in README
