---
name: web-fetch
description: Fetch and read web page content, APIs, documentation
triggers: [fetch, url, webpage, website, http, api call, documentation, read url, curl, download]
---

## Web Fetch

Use the `web_fetch` tool to read web content. HTML tags are automatically stripped.

### Use cases
- Read documentation pages
- Check API endpoints
- Fetch JSON from REST APIs
- Read README from GitHub raw URLs
- Check website status/content

### Tips
- For GitHub files, use raw URL: `https://raw.githubusercontent.com/owner/repo/branch/file`
- For API endpoints, the JSON response will be pretty-printed
- Results are auto-truncated if too long
- For large pages, consider fetching specific sections via API instead

### Examples
```
web_fetch: {"url": "https://api.github.com/repos/owner/repo"}
web_fetch: {"url": "https://raw.githubusercontent.com/owner/repo/main/README.md"}
web_fetch: {"url": "https://httpbin.org/json"}
```

### Limitations
- Cannot execute JavaScript (static content only)
- Cannot handle authentication (no cookies/tokens)
- Timeout: 15 seconds
- Max redirects: 3
