---
name: x-twitter
description: Interact with X (Twitter) via xurl CLI or API
triggers: [twitter, x, tweet, post, timeline, xurl, x api, social media]
---

## X (Twitter) via xurl CLI

### Setup
Install xurl: https://github.com/xdevplatform/xurl

```bash
# macOS
brew install --cask xdevplatform/tap/xurl

# npm
npm install -g @xdevplatform/xurl

# Authenticate (one-time, interactive)
xurl auth oauth2
xurl auth status                      # verify
```

### Posting

```bash
# Simple post
xurl post "Hello world!"

# Post with media
xurl media upload photo.jpg           # get media_id
xurl post "Check this out" --media-id MEDIA_ID

# Reply
xurl reply POST_ID "Great point!"
xurl reply https://x.com/user/status/123 "Agreed!"

# Quote
xurl quote POST_ID "My thoughts"

# Delete
xurl delete POST_ID
```

### Reading

```bash
# Read a post
xurl read POST_ID
xurl read https://x.com/user/status/123

# Search
xurl search "golang" -n 10
xurl search "from:elonmusk" -n 20

# Timeline & mentions
xurl timeline -n 20
xurl mentions -n 10
```

### Engagement

```bash
# Like / unlike
xurl like POST_ID
xurl unlike POST_ID

# Repost / undo
xurl repost POST_ID
xurl unrepost POST_ID

# Bookmark
xurl bookmark POST_ID
xurl bookmarks -n 20
```

### Social

```bash
# User info
xurl whoami
xurl user @handle

# Follow / unfollow
xurl follow @handle
xurl unfollow @handle

# Lists
xurl following -n 50
xurl followers -n 50
```

### Direct Messages

```bash
xurl dm @user "Hey!"
xurl dms -n 10
```

### Rules
- Post IDs and full URLs both work as identifiers
- `@` prefix is optional for usernames
- Never use `--verbose` flag (can leak auth tokens)
- Never read/display `~/.xurl` file (contains tokens)
- Rate limits apply — write endpoints are stricter than reads
- All output is JSON — pipe through `jq` for formatting
