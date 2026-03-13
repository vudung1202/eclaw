---
name: debug-errors
description: Debug errors, exceptions, stack traces, troubleshooting
triggers: [debug, error, exception, stack trace, crash, bug, fix, troubleshoot, issue, fail, broken, not working, stacktrace, traceback]
---

## Debug & Error Resolution

### Approach
1. **Read the error message** — most errors tell you exactly what's wrong
2. **Find the stack trace** — locate the first line in YOUR code (not library code)
3. **Reproduce** — can you trigger it reliably?
4. **Isolate** — what's the minimal case that fails?
5. **Fix & verify** — fix the root cause, not the symptom

### Elixir/Erlang errors
```elixir
# Common errors
** (FunctionClauseError)     → no matching function clause
** (KeyError)                → missing map key
** (MatchError)              → pattern match failed
** (ArgumentError)           → wrong argument type/value
** (UndefinedFunctionError)  → function doesn't exist
** (Protocol.UndefinedError) → protocol not implemented

# Debug in IEx
IEx.pry()                     # breakpoint (add to code)
dbg(value)                    # Elixir 1.14+ debug macro
IO.inspect(value, label: "x") # print and pass through
Process.info(pid)             # process details
:sys.get_state(pid)           # GenServer state
```

### Reading stack traces
```
** (KeyError) key :name not found in: %{username: "alice"}
    (my_app 0.1.0) lib/my_app/users.ex:42: MyApp.Users.format/1
    (my_app 0.1.0) lib/my_app_web/controllers/user_controller.ex:15: ...
    (phoenix 1.7.0) lib/phoenix/router.ex:...
```
→ Look at `lib/my_app/users.ex:42` — that's YOUR code
→ The error is accessing `.name` but the map has `.username`

### Bash debugging
```bash
# Run with debug output
bash -x script.sh

# Check exit code
echo $?

# Common: command not found
which command_name
type command_name

# Permission denied
ls -la file
chmod +x script.sh
```

### Log analysis
```bash
# Find errors in logs
grep -i "error\|exception\|fail" log/dev.log | tail -20

# Context around error
grep -B5 -A10 "ERROR" log/dev.log | tail -40

# Error frequency
grep -c "ERROR" log/dev.log
```

### Common patterns
- **nil/null errors** → check if data exists before accessing
- **timeout** → is the service running? network issue? slow query?
- **connection refused** → wrong port? service not started?
- **permission denied** → file permissions, sudo needed?
- **out of memory** → unbounded data? memory leak?

### Rules
- Read the FULL error message before guessing
- Fix root cause, not symptoms
- Add `IO.inspect` / `dbg` for Elixir debugging
- Check logs with `grep -i error` first
- Don't ignore warnings — they often predict errors
