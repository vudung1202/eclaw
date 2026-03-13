---
name: browser
description: Web browsing, fetching web pages, scraping content
triggers: [browse, web page, website, url, fetch, scrape, download, http, https, crawl, open url]
---

## Web Browsing & Fetching

### Fetch web content
```bash
# Simple GET
curl -s https://example.com

# Follow redirects
curl -sL https://example.com

# Save to file
curl -sL -o page.html https://example.com

# With headers
curl -s -H "User-Agent: Mozilla/5.0" https://example.com

# Just headers
curl -sI https://example.com

# Download file
curl -sL -O https://example.com/file.zip
wget https://example.com/file.zip
```

### Extract content from HTML
```bash
# Strip HTML tags (basic)
curl -s https://example.com | sed 's/<[^>]*>//g' | tr -s '[:space:]' '\n' | head -50

# Extract links
curl -s https://example.com | grep -oP 'href="\K[^"]+' | head -20

# Extract title
curl -s https://example.com | grep -oP '<title>\K[^<]+'
```

### Or use `web_fetch` tool
The `web_fetch` tool fetches a URL, strips HTML, and returns clean text.
Use it for simple page reading without bash complexity.

### Check website status
```bash
# HTTP status code
curl -s -o /dev/null -w "%{http_code}" https://example.com

# Response time
curl -s -o /dev/null -w "%{time_total}" https://example.com

# Full timing breakdown
curl -s -o /dev/null -w "DNS: %{time_namelookup}s\nConnect: %{time_connect}s\nTTFB: %{time_starttransfer}s\nTotal: %{time_total}s\n" https://example.com
```

### Rules
- Use `web_fetch` tool for simple page reads
- Use `curl` for advanced needs (POST, headers, auth)
- Always limit output with `head` or filters
- Respect robots.txt and rate limits
- Don't fetch unnecessary pages — be targeted
