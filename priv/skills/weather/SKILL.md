---
name: weather
description: Get current weather conditions and forecasts via wttr.in
triggers: [weather, forecast, temperature, rain, wind, humidity, climate]
---

## Weather (via wttr.in)

No API key needed. Uses [wttr.in](https://wttr.in).

### When to Use
- "What's the weather in Hanoi?"
- "Will it rain today?"
- "Temperature in Ho Chi Minh City"
- Travel planning weather checks

### Current Weather

```bash
# One-line summary
curl -s "wttr.in/Hanoi?format=3"

# Detailed current conditions
curl -s "wttr.in/Hanoi?0"

# Custom format
curl -s "wttr.in/Hanoi?format=%l:+%c+%t+(feels+like+%f),+%w+wind,+%h+humidity"
```

### Forecasts

```bash
# 3-day forecast
curl -s "wttr.in/Hanoi"

# Compact forecast
curl -s "wttr.in/Hanoi?format=v2"

# Specific day (0=today, 1=tomorrow, 2=day after)
curl -s "wttr.in/Hanoi?1"
```

### Format Codes

| Code | Meaning |
|------|---------|
| `%c` | Weather condition emoji |
| `%t` | Temperature |
| `%f` | "Feels like" |
| `%w` | Wind |
| `%h` | Humidity |
| `%p` | Precipitation |
| `%l` | Location |

### JSON output
```bash
curl -s "wttr.in/Hanoi?format=j1" | jq '.current_condition[0] | {temp_C, humidity, weatherDesc: .weatherDesc[0].value}'
```

### Quick Responses

```bash
# "What's the weather?"
curl -s "wttr.in/Hanoi?format=%l:+%c+%t+(feels+like+%f),+%w+wind,+%h+humidity"

# "Will it rain?"
curl -s "wttr.in/Hanoi?format=%l:+%c+%p"
```

### Rules
- Always include a city name in the query
- Supports airport codes: `curl wttr.in/SGN` (Tan Son Nhat)
- No API key needed
- Rate limited — don't spam requests
- Works for most global cities
