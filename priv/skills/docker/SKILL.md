---
name: docker
description: Docker containers, images, Docker Compose, container orchestration
triggers: [docker, container, image, dockerfile, compose, docker-compose, volume, network, registry, build image]
---

## Docker & Docker Compose

### When to Use
- Running services in isolated containers
- Building and deploying containerized applications
- Managing multi-service stacks with Docker Compose
- Debugging container issues

### Container Management

```bash
# List running containers
docker ps
docker ps -a                          # include stopped

# Run container
docker run -d --name myapp -p 4000:4000 myimage
docker run -it --rm alpine sh         # interactive, auto-remove

# Stop / start / restart
docker stop myapp
docker start myapp
docker restart myapp

# Remove
docker rm myapp                       # stopped container
docker rm -f myapp                    # force remove running

# Logs
docker logs myapp
docker logs -f myapp                  # follow
docker logs --tail 100 myapp          # last 100 lines

# Execute in container
docker exec -it myapp sh
docker exec -it myapp bash
docker exec myapp ls /app
```

### Images

```bash
# List images
docker images

# Build
docker build -t myapp:latest .
docker build -t myapp:latest -f Dockerfile.prod .

# Remove image
docker rmi myapp:latest

# Clean up
docker system prune                   # unused data
docker system prune -a                # all unused images
docker image prune                    # dangling images
```

### Docker Compose

```bash
# Start services
docker compose up -d
docker compose up -d --build          # rebuild images

# Stop
docker compose down
docker compose down -v                # remove volumes too

# Status
docker compose ps
docker compose logs -f
docker compose logs -f service_name

# Rebuild single service
docker compose up -d --build service_name

# Execute in service
docker compose exec service_name sh

# Scale
docker compose up -d --scale worker=3
```

### Compose file example
```yaml
# docker-compose.yml
services:
  app:
    build: .
    ports:
      - "4000:4000"
    environment:
      - DATABASE_URL=postgres://postgres:postgres@db/myapp
    depends_on:
      - db

  db:
    image: postgres:16-alpine
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      - POSTGRES_PASSWORD=postgres

volumes:
  pgdata:
```

### Debugging

```bash
# Inspect container
docker inspect myapp
docker inspect myapp | jq '.[0].NetworkSettings.IPAddress'

# Resource usage
docker stats
docker stats myapp

# Check container health
docker inspect --format='{{.State.Health.Status}}' myapp

# Copy files
docker cp myapp:/app/log/error.log ./error.log
docker cp ./config.json myapp:/app/config.json
```

### Volumes & Networks

```bash
# Volumes
docker volume ls
docker volume create mydata
docker volume inspect mydata
docker volume rm mydata

# Networks
docker network ls
docker network create mynet
docker network connect mynet myapp
```

### Elixir Dockerfile (multi-stage)
```dockerfile
FROM elixir:1.18-alpine AS build
WORKDIR /app
ENV MIX_ENV=prod
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile
COPY . .
RUN mix release

FROM alpine:3.19
RUN apk add --no-cache libstdc++ openssl ncurses-libs
COPY --from=build /app/_build/prod/rel/myapp ./app
CMD ["./app/bin/myapp", "start"]
```

### Rules
- Use `-d` for background (daemon) mode
- Always name containers (`--name`) for easier management
- Use `docker compose` (v2) not `docker-compose` (v1)
- Clean up unused resources with `docker system prune`
- Use multi-stage builds for smaller production images
