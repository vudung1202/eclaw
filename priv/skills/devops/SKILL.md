---
name: devops
description: Docker, deployment, CI/CD, server management, infrastructure
triggers: [docker, deploy, ci, cd, pipeline, server, nginx, systemd, container, kubernetes, k8s, compose, infrastructure]
---

## DevOps Operations

### Docker
```bash
docker ps -a                              # all containers
docker logs --tail 100 <container>        # recent logs
docker logs -f <container>                # follow logs
docker compose ps                         # compose status
docker compose logs --tail 50 <service>   # compose logs
docker compose up -d                      # start in background
docker compose down                       # stop
docker build -t name:tag .                # build image
docker exec -it <container> sh            # shell into container
```

### GitHub Actions CI/CD
```bash
gh run list --limit 10                    # recent workflow runs
gh run view <id>                          # run details
gh run view <id> --log-failed             # failed job logs
gh workflow list                          # available workflows
gh workflow run <name>                    # trigger workflow
```

### Server diagnostics
```bash
# Ports & connections
lsof -i :<port>
ss -tlnp
netstat -tlnp

# Processes
ps aux | grep <name>
top -bn1 | head -20

# Disk & memory
df -h
du -sh /path/*
free -h          # Linux
vm_stat           # macOS

# Logs
journalctl -u <service> --since "1 hour ago"
tail -100 /var/log/syslog
```

### Nginx
```bash
nginx -t                                  # test config
nginx -s reload                           # reload config
cat /etc/nginx/sites-enabled/*            # view sites
```

### Rules
- Always check status before making changes
- Show logs when debugging issues
- Explain what commands do before running destructive ones
