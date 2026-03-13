---
name: deployment
description: Deploy applications, manage releases, CI/CD pipelines
triggers: [deploy, release, build, ship, publish, fly.io, heroku, aws, gcp, digital ocean, vercel, netlify, gigalixir, render]
---

## Deployment

### Elixir releases
```bash
MIX_ENV=prod mix release
_build/prod/rel/app/bin/app start
_build/prod/rel/app/bin/app daemon        # background
_build/prod/rel/app/bin/app remote        # remote IEx
```

### Docker deployment
```dockerfile
# Multi-stage build
FROM elixir:1.18-alpine AS build
WORKDIR /app
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
COPY . .
RUN MIX_ENV=prod mix release

FROM alpine:3.19
COPY --from=build /app/_build/prod/rel/app ./app
CMD ["./app/bin/app", "start"]
```

### Fly.io
```bash
fly launch
fly deploy
fly status
fly logs
fly ssh console
fly secrets set KEY=value
```

### Pre-deployment checklist
- [ ] All tests pass: `mix test`
- [ ] No compiler warnings: `mix compile --warnings-as-errors`
- [ ] Environment variables set on target
- [ ] Database migrations ready
- [ ] Secrets not in code
- [ ] Health check endpoint working

### Rollback
```bash
# Fly.io
fly releases
fly deploy --image <previous-image>

# Docker
docker compose up -d --force-recreate <service>

# Elixir
mix ecto.rollback --step 1
```
