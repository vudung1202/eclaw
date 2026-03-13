---
name: web-search
description: Search the web for information, docs, solutions
triggers: [search, google, look up, find online, search web, how to, what is, stackoverflow]
---

## Web Search

When user needs information from the web:

### Strategy
1. For coding questions — search documentation sites directly:
   ```
   web_fetch: {"url": "https://hexdocs.pm/phoenix/overview.html"}
   web_fetch: {"url": "https://docs.github.com/en/rest/pulls"}
   ```

2. For API references — fetch the API docs:
   ```
   web_fetch: {"url": "https://api.github.com"}
   ```

3. For general questions — use bash with `curl`:
   ```bash
   curl -s "https://api.duckduckgo.com/?q=elixir+genserver&format=json" | head -500
   ```

### Common documentation URLs
- Elixir: `https://hexdocs.pm/<package>`
- Phoenix: `https://hexdocs.pm/phoenix`
- Ecto: `https://hexdocs.pm/ecto`
- Node.js: `https://nodejs.org/api/`
- Python: `https://docs.python.org/3/`
- GitHub API: `https://api.github.com`
- MDN Web: `https://developer.mozilla.org/en-US/docs/Web`

### Rules
- Prefer official docs over random blog posts
- Fetch specific pages, not homepages
- Summarize findings concisely
