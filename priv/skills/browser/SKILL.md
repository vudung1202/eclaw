---
name: browser
description: Web browsing, fetching web pages, scraping content, browser automation
triggers: [browse, web page, website, url, fetch, scrape, download, http, https, crawl, open url, screenshot, click, form, playwright]
---

## Web Browsing & Fetching

### Tool selection guide

| Need | Tool | Requires |
|------|------|----------|
| Read page text, call APIs | `web_fetch` | Nothing (built-in) |
| Advanced HTTP (POST, headers, auth) | `execute_bash` + `curl` | Nothing |
| JS-rendered pages, SPAs | `browser_navigate` | Playwright + Chromium |
| Screenshots | `browser_screenshot` | Playwright + Chromium |
| Click/type/interact | `browser_click` / `browser_type` | Playwright + Chromium |
| Run JS in page context | `browser_evaluate` | Playwright + Chromium |

### web_fetch (recommended for most cases)

The `web_fetch` tool fetches a URL, strips HTML, and returns clean text.
Use it for simple page reading, real-time data (prices, news, weather), and API calls.

```
tool: web_fetch
input: {"url": "https://example.com"}
```

### curl via bash

```bash
# Simple GET
curl -s https://example.com

# Follow redirects + save
curl -sL -o page.html https://example.com

# POST JSON
curl -s -X POST -H "Content-Type: application/json" -d '{"key":"value"}' https://api.example.com

# Just headers / status code
curl -sI https://example.com
curl -s -o /dev/null -w "%{http_code}" https://example.com
```

### Extract content from HTML (bash)

```bash
# Strip HTML tags
curl -s https://example.com | sed 's/<[^>]*>//g' | tr -s '[:space:]' '\n' | head -50

# Extract links
curl -s https://example.com | grep -oP 'href="\K[^"]+' | head -20

# Extract title
curl -s https://example.com | grep -oP '<title>\K[^<]+'
```

## Browser Automation (Playwright)

Requires one-time setup:
```bash
npx playwright install chromium
```

These tools use a real Chromium browser — needed for JS-rendered pages, SPAs, screenshots, and form interaction.

### browser_navigate
Open a URL and get the page text content (after JS renders).
```
tool: browser_navigate
input: {"url": "https://example.com", "wait_for": ".content"}
```

### browser_screenshot
Take a screenshot of a page or specific element.
```
tool: browser_screenshot
input: {"url": "https://example.com", "full_page": true}
tool: browser_screenshot
input: {"url": "https://example.com", "selector": "#chart"}
```

### browser_click
Click an element by CSS selector.
```
tool: browser_click
input: {"url": "https://example.com", "selector": "button.submit"}
```

### browser_type
Type text into an input field.
```
tool: browser_type
input: {"url": "https://example.com", "selector": "#search", "text": "query"}
```

### browser_evaluate
Execute JavaScript in the browser and return results.
```
tool: browser_evaluate
input: {"url": "https://example.com", "script": "document.querySelectorAll('h2').length"}
```

## Rules
- Prefer `web_fetch` for simple reads — faster, no browser overhead
- Use `browser_*` only when JS rendering or interaction is needed
- Always limit output with `head` or filters when using bash
- Respect robots.txt and rate limits
- Don't fetch unnecessary pages — be targeted
