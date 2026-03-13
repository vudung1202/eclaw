---
name: notion
description: Interact with Notion API for pages, databases, and content management
triggers: [notion, notion api, workspace, wiki, knowledge base, notion page, notion database]
---

## Notion API

### Setup
1. Create integration at https://www.notion.so/my-integrations
2. Get the Internal Integration Token
3. Share target pages/databases with the integration (click "..." → "Connect to")

```bash
export NOTION_API_KEY="ntn_..."
```

### Search

```bash
# Search across workspace
curl -s -X POST "https://api.notion.com/v1/search" \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d '{"query": "search term"}' | jq '.results[] | {id, title: .properties.title.title[0].plain_text}'
```

### Pages

```bash
# Get page
curl -s "https://api.notion.com/v1/pages/PAGE_ID" \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2022-06-28" | jq

# Get page content (blocks)
curl -s "https://api.notion.com/v1/blocks/PAGE_ID/children" \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2022-06-28" | jq '.results[] | {type, text: .paragraph.rich_text[0].plain_text}'

# Create page in database
curl -s -X POST "https://api.notion.com/v1/pages" \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d '{
    "parent": {"database_id": "DB_ID"},
    "properties": {
      "Name": {"title": [{"text": {"content": "New Item"}}]},
      "Status": {"select": {"name": "In Progress"}}
    }
  }' | jq '{id, url}'
```

### Databases

```bash
# Query database
curl -s -X POST "https://api.notion.com/v1/databases/DB_ID/query" \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d '{
    "filter": {"property": "Status", "select": {"equals": "In Progress"}},
    "sorts": [{"property": "Created", "direction": "descending"}]
  }' | jq '.results[] | {id, name: .properties.Name.title[0].plain_text}'
```

### Append content to page

```bash
curl -s -X PATCH "https://api.notion.com/v1/blocks/PAGE_ID/children" \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d '{
    "children": [
      {"paragraph": {"rich_text": [{"text": {"content": "New paragraph text"}}]}}
    ]
  }'
```

### Rules
- Always include `Notion-Version: 2022-06-28` header
- Pages/databases must be shared with the integration first
- Rate limit: ~3 requests/second
- Max 100 blocks per append
- Never log or display the API token
