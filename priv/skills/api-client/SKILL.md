---
name: api-client
description: Interact with REST APIs, GraphQL, webhooks
triggers: [api, rest, graphql, endpoint, webhook, http request, curl, postman, request, response, json api]
---

## API Client

### REST API calls via bash
```bash
# GET
curl -s https://api.example.com/data | jq

# GET with headers
curl -s -H "Authorization: Bearer TOKEN" https://api.example.com/data | jq

# POST JSON
curl -s -X POST https://api.example.com/data \
  -H "Content-Type: application/json" \
  -d '{"key": "value"}' | jq

# PUT
curl -s -X PUT https://api.example.com/data/1 \
  -H "Content-Type: application/json" \
  -d '{"key": "updated"}' | jq

# DELETE
curl -s -X DELETE https://api.example.com/data/1
```

### GitHub API (via gh)
```bash
gh api repos/{owner}/{repo}
gh api repos/{owner}/{repo}/pulls
gh api repos/{owner}/{repo}/issues --jq '.[].title'
gh api graphql -f query='{ viewer { login } }'
```

### Response handling
```bash
# Status code only
curl -s -o /dev/null -w "%{http_code}" https://api.example.com

# Headers + body
curl -s -i https://api.example.com | head -20

# Pretty JSON
curl -s https://api.example.com | jq '.'

# Filter JSON
curl -s https://api.example.com/users | jq '.[0:5] | .[] | {name, email}'
```

### Or use `web_fetch` tool for simple GET requests.

### Rules
- Never log or display API tokens/secrets
- Use `jq` to format JSON output
- Add timeout: `curl -s --max-time 10`
- For large responses, pipe through `head` or `jq` filter
