---
name: monitoring
description: Application monitoring, logging, error tracking, observability
triggers: [monitor, logging, log, error tracking, sentry, observability, metrics, health check, uptime, alert]
---

## Monitoring & Observability

### Application logs
```bash
# Elixir/Phoenix
tail -f log/dev.log
tail -f log/prod.log
grep -i "error\|warn" log/prod.log | tail -20

# Docker
docker logs --tail 100 -f <container>
docker compose logs --tail 100 -f <service>

# systemd
journalctl -u <service> -f
journalctl -u <service> --since "1 hour ago"
journalctl -u <service> -p err            # errors only
```

### Health checks
```bash
curl -s http://localhost:4000/api/status | jq
curl -s -o /dev/null -w "%{http_code}" http://localhost:4000/
```

### Process monitoring
```bash
# Check if service is running
ps aux | grep <name>
pgrep -f <pattern>
systemctl status <service>

# Port check
lsof -i :4000
curl -s localhost:4000 > /dev/null && echo "UP" || echo "DOWN"
```

### Elixir/BEAM monitoring
```elixir
# In IEx
:observer.start()                         # full GUI
Process.list() |> length()               # process count
:erlang.memory()                         # memory by type
:erlang.system_info(:process_count)      # active processes
:ets.all() |> length()                   # ETS tables
```

### Key metrics to watch
- Response time (p50, p95, p99)
- Error rate (5xx responses)
- Memory usage trend
- Process count (BEAM)
- Database connection pool
- Queue depth / backlog
