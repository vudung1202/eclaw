---
name: discord
description: Send messages and interact with Discord via webhooks and bot API
triggers: [discord, discord bot, discord webhook, discord api, discord channel, discord server]
---

## Discord Integration

### Webhooks (simplest — send only)

```bash
# Send message via webhook
curl -s -X POST "$DISCORD_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"content": "Hello from Eclaw!"}'

# With embed (rich message)
curl -s -X POST "$DISCORD_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Deploy notification",
    "embeds": [{
      "title": "Deploy Completed",
      "description": "Version 1.2.3 deployed to production",
      "color": 5763719,
      "fields": [
        {"name": "Environment", "value": "Production", "inline": true},
        {"name": "Status", "value": "Success", "inline": true}
      ]
    }]
  }'

# With username/avatar override
curl -s -X POST "$DISCORD_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"content": "Alert!", "username": "Eclaw Bot", "avatar_url": "https://example.com/avatar.png"}'
```

### Bot API

```bash
export DISCORD_TOKEN="Bot YOUR_BOT_TOKEN"

# Send message to channel
curl -s -X POST "https://discord.com/api/v10/channels/{channelId}/messages" \
  -H "Authorization: $DISCORD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content": "Hello!"}' | jq

# Read messages
curl -s "https://discord.com/api/v10/channels/{channelId}/messages?limit=10" \
  -H "Authorization: $DISCORD_TOKEN" | jq '.[] | {author: .author.username, content}'

# Add reaction
curl -s -X PUT "https://discord.com/api/v10/channels/{channelId}/messages/{messageId}/reactions/%E2%9C%85/@me" \
  -H "Authorization: $DISCORD_TOKEN"

# List guilds (servers)
curl -s "https://discord.com/api/v10/users/@me/guilds" \
  -H "Authorization: $DISCORD_TOKEN" | jq '.[] | {name, id}'

# List channels in guild
curl -s "https://discord.com/api/v10/guilds/{guildId}/channels" \
  -H "Authorization: $DISCORD_TOKEN" | jq '.[] | {name, id, type}'
```

### Embed Colors
```
Green:  5763719  (0x57F287)
Red:    15548997 (0xED4245)
Blue:   5793266  (0x5865F2)
Yellow: 16776960 (0xFFFF00)
```

### Rules
- Use webhooks for simple notifications (no bot setup needed)
- Use Bot API for interactive features
- Token format: `Bot <token>` for bot tokens
- Rate limits: 5 requests/5s per channel for messages
- Never log or display tokens
