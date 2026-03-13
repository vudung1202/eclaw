---
name: slack
description: Send messages and interact with Slack via webhooks and API
triggers: [slack, slack api, webhook, slack message, slack channel, slack bot, team chat]
---

## Slack Integration

### Incoming Webhooks (simplest — send only)

```bash
# Send message via webhook
curl -s -X POST "$SLACK_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello from Eclaw!"}'

# With formatting
curl -s -X POST "$SLACK_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "*Deploy completed* :white_check_mark:",
    "blocks": [
      {
        "type": "section",
        "text": {"type": "mrkdwn", "text": "*Deploy completed* :white_check_mark:\nVersion `1.2.3` deployed to production"}
      }
    ]
  }'
```

### Slack Web API (full access)

```bash
export SLACK_TOKEN="xoxb-..."

# Send message to channel
curl -s -X POST "https://slack.com/api/chat.postMessage" \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"channel": "C0123456789", "text": "Hello!"}' | jq

# List channels
curl -s "https://slack.com/api/conversations.list" \
  -H "Authorization: Bearer $SLACK_TOKEN" | jq '.channels[] | {name, id}'

# Read messages
curl -s "https://slack.com/api/conversations.history?channel=C0123456789&limit=10" \
  -H "Authorization: Bearer $SLACK_TOKEN" | jq '.messages[] | {user, text, ts}'

# React to message
curl -s -X POST "https://slack.com/api/reactions.add" \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"channel": "C0123456789", "timestamp": "1234567890.123456", "name": "thumbsup"}'

# Upload file
curl -s -X POST "https://slack.com/api/files.uploadV2" \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -F "channel_id=C0123456789" \
  -F "title=Report" \
  -F "file=@report.txt"
```

### Common Use Cases

```bash
# Notify on deploy
curl -s -X POST "$SLACK_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "{\"text\": \"Deployed $(git rev-parse --short HEAD) to production\"}"

# Alert on error
curl -s -X POST "$SLACK_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"text": ":rotating_light: Error rate exceeded threshold"}'
```

### Rules
- Use webhooks for simple notifications (no token needed, just the URL)
- Use Web API for interactive features (reading, reacting, uploading)
- Never log or display tokens
- Channel IDs start with `C` (public) or `G` (private)
- Rate limits: ~1 request/second for Web API
