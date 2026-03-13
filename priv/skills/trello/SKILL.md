---
name: trello
description: Manage Trello boards, lists, and cards via REST API
triggers: [trello, board, card, kanban, task board, sprint board, trello api]
---

## Trello API

### Setup
1. Get API key: https://trello.com/app-key
2. Generate token (click "Token" link on that page)

```bash
export TRELLO_API_KEY="your-api-key"
export TRELLO_TOKEN="your-token"
```

### Boards

```bash
# List your boards
curl -s "https://api.trello.com/1/members/me/boards?key=$TRELLO_API_KEY&token=$TRELLO_TOKEN" \
  | jq '.[] | {name, id}'

# Find board by name
curl -s "https://api.trello.com/1/members/me/boards?key=$TRELLO_API_KEY&token=$TRELLO_TOKEN" \
  | jq '.[] | select(.name | contains("Project"))'
```

### Lists

```bash
# List all lists in a board
curl -s "https://api.trello.com/1/boards/{boardId}/lists?key=$TRELLO_API_KEY&token=$TRELLO_TOKEN" \
  | jq '.[] | {name, id}'
```

### Cards

```bash
# List cards in a list
curl -s "https://api.trello.com/1/lists/{listId}/cards?key=$TRELLO_API_KEY&token=$TRELLO_TOKEN" \
  | jq '.[] | {name, id, desc}'

# Create a card
curl -s -X POST "https://api.trello.com/1/cards?key=$TRELLO_API_KEY&token=$TRELLO_TOKEN" \
  -d "idList={listId}" \
  -d "name=Card Title" \
  -d "desc=Card description"

# Move card to another list
curl -s -X PUT "https://api.trello.com/1/cards/{cardId}?key=$TRELLO_API_KEY&token=$TRELLO_TOKEN" \
  -d "idList={newListId}"

# Add comment
curl -s -X POST "https://api.trello.com/1/cards/{cardId}/actions/comments?key=$TRELLO_API_KEY&token=$TRELLO_TOKEN" \
  -d "text=Your comment here"

# Archive card
curl -s -X PUT "https://api.trello.com/1/cards/{cardId}?key=$TRELLO_API_KEY&token=$TRELLO_TOKEN" \
  -d "closed=true"
```

### Rules
- Board/List/Card IDs can be found in the Trello URL or via API
- Rate limits: 300 requests/10s per API key, 100 requests/10s per token
- Keep API key and token secret
- Use `jq` to filter JSON responses
