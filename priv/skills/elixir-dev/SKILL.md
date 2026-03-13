---
name: elixir-dev
description: Elixir, Phoenix, LiveView, OTP development assistance
triggers: [elixir, phoenix, mix, iex, ecto, liveview, genserver, otp, supervisor, plug, absinthe, nerves]
---

## Elixir & Phoenix Development

### Project commands
```bash
mix compile                         # compile
mix compile --warnings-as-errors    # strict
mix test                            # all tests
mix test test/path_test.exs:42      # specific line
mix test --failed                   # rerun failed
mix format                          # format code
mix deps.get                        # install deps
mix deps.update --all               # update all deps
mix phx.routes                      # list routes
mix phx.gen.context Accounts User users name:string email:string
mix phx.gen.live Accounts User users name:string email:string
```

### Debugging
```elixir
# In IEx
iex -S mix
iex -S mix phx.server               # with Phoenix
:observer.start()                   # GUI observer
Process.info(pid)                   # process details
:sys.get_state(pid)                 # GenServer state
```

### Patterns
- **GenServer**: stateful processes with `handle_call/cast/info`
- **Supervisor**: `one_for_one`, `one_for_all`, `rest_for_one`
- **DynamicSupervisor**: start children at runtime
- **Registry**: process discovery by name
- **Task.async_stream**: parallel work with backpressure
- **with**: chain failable operations cleanly
- **Ecto.Multi**: atomic database transactions

### Phoenix conventions
- Contexts for business logic boundaries
- Schemas for data, changesets for validation
- Controllers → Views → Templates (or LiveView)
- PubSub for real-time features
- Plugs for middleware

### Common issues
- `** (UndefinedFunctionError)` → check module name, function arity
- `** (CompileError)` → syntax error, run `mix compile` to see details
- `(EXIT) shutdown` → child process failed to start, check init/1
- Migration errors → `mix ecto.rollback` then fix and re-migrate
