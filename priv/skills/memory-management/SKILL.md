---
name: memory-management
description: Memory management, context window optimization, conversation history
triggers: [memory, context, remember, forget, history, conversation, context window, token, compact, summarize]
---

## Memory Management

### Conversation context
- Monitor context window usage — compact when approaching limits
- Keep recent messages (last 4 exchanges) for continuity
- Summarize older context instead of keeping full history
- Token estimation: ~3.5 characters per token

### When to compact
- Input tokens exceed budget (default 8K)
- Approaching model context window limit
- After long tool-heavy exchanges

### Memory persistence
```
# Save important facts for future sessions
- User preferences
- Project conventions
- Key decisions made

# Don't persist
- Debugging details (ephemeral)
- Full file contents (re-read when needed)
- Intermediate results
```

### Rules
- Always preserve the user's most recent message
- Summarize before dropping — never silently lose context
- Keep tool results concise (truncate large outputs)
- Re-read files rather than relying on stale context
