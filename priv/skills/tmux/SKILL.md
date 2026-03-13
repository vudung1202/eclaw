---
name: tmux
description: Terminal multiplexer for managing sessions, windows, and panes
triggers: [tmux, terminal multiplexer, session, pane, window, split, detach, attach]
---

## tmux — Terminal Multiplexer

### When to Use
- Managing multiple terminal sessions
- Running long processes that survive disconnects
- Monitoring multiple services simultaneously
- Pair programming / sharing terminal sessions

### Session Management

```bash
# List sessions
tmux list-sessions
tmux ls

# New session
tmux new-session -s work
tmux new -s work

# Attach to session
tmux attach -t work
tmux a -t work

# Detach (inside tmux)
# Ctrl+B, then D

# Kill session
tmux kill-session -t work

# Rename session
tmux rename-session -t old new
```

### Windows (tabs)

```bash
# New window
# Ctrl+B, C

# Switch windows
# Ctrl+B, 0-9          (by number)
# Ctrl+B, N            (next)
# Ctrl+B, P            (previous)

# Rename window
# Ctrl+B, ,

# Close window
# Ctrl+B, &
```

### Panes (splits)

```bash
# Split horizontally
# Ctrl+B, "

# Split vertically
# Ctrl+B, %

# Navigate panes
# Ctrl+B, arrow keys

# Resize panes
# Ctrl+B, Ctrl+arrow keys

# Close pane
# Ctrl+B, X

# Toggle pane zoom (fullscreen)
# Ctrl+B, Z
```

### Scripted Control

```bash
# Send keys to a pane
tmux send-keys -t session:0.0 "npm start" Enter

# Capture pane output
tmux capture-pane -t session -p | tail -20

# Create a dev layout
tmux new-session -d -s dev
tmux send-keys -t dev "vim" Enter
tmux split-window -h -t dev
tmux send-keys -t dev "npm run dev" Enter
tmux split-window -v -t dev
tmux send-keys -t dev "tail -f log/dev.log" Enter
tmux attach -t dev
```

### Target Format
```
session:window.pane
# Examples:
work:0.0          # session "work", window 0, pane 0
work:editor       # session "work", window named "editor"
```

### Rules
- Use named sessions for organization (`tmux new -s project-name`)
- `Ctrl+B` is the default prefix key
- Use `tmux capture-pane -p` to read output programmatically
- Sessions persist after detach — reconnect with `tmux a -t name`
