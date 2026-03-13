---
name: performance
description: Performance analysis, profiling, optimization
triggers: [performance, slow, optimize, profiling, benchmark, memory leak, cpu, latency, bottleneck, n+1, cache]
---

## Performance Analysis

### System diagnostics
```bash
# CPU & memory
top -bn1 | head -20                       # Linux
ps aux --sort=-%mem | head -10            # top memory processes
ps aux --sort=-%cpu | head -10            # top CPU processes

# Disk I/O
iostat -x 1 3 2>/dev/null || vm_stat     # macOS fallback

# Network
ss -s                                     # socket summary
netstat -s | head -20                     # network stats
```

### Elixir/BEAM profiling
```elixir
# In IEx
:timer.tc(fn -> MyModule.function() end)  # measure time
:fprof.apply(&MyModule.function/0, [])    # function profiling
:observer.start()                         # GUI: processes, memory, ETS
Process.list() |> length()                # process count
:erlang.memory()                          # memory breakdown
```

### Database performance
```sql
EXPLAIN ANALYZE SELECT ...;               # query plan
SELECT * FROM pg_stat_user_tables;        # table stats
SELECT * FROM pg_stat_user_indexes;       # index usage
-- Find slow queries
SELECT query, mean_exec_time, calls FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;
```

### Common issues & fixes
| Issue | Detection | Fix |
|-------|-----------|-----|
| N+1 queries | Multiple SELECTs in loop | Use `preload` / `JOIN` |
| Missing index | Seq Scan in EXPLAIN | Add index on queried columns |
| Memory leak | Growing memory in observer | Check ETS tables, process mailboxes |
| Slow API | High latency in logs | Add caching, reduce payload |
| Large payload | Response size in network tab | Pagination, field selection |

### Rules
- Measure before optimizing — don't guess
- Profile the hot path first
- One change at a time, measure impact
