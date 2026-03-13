---
name: shell-tools
description: Shell scripting, command line tools, system administration
triggers: [shell, bash, zsh, terminal, command line, cli, pipe, script, cron, crontab, alias, env, path, process, kill, signal]
---

## Shell & CLI Tools

### Process management
```bash
ps aux | grep <name>                      # find process
kill <pid>                                # graceful stop
kill -9 <pid>                             # force kill
pkill -f <pattern>                        # kill by name pattern
lsof -i :<port>                           # what's using a port
```

### Environment
```bash
env | grep KEY                            # check env var
echo $PATH                               # PATH
which <command>                           # command location
type <command>                            # command type
```

### Text processing pipeline
```bash
# Chain with pipes
cat file | grep "pattern" | sort | uniq -c | sort -rn | head -10

# sed - search & replace
sed 's/old/new/g' file                    # replace all occurrences
sed -n '10,20p' file                      # print lines 10-20
sed -i '' 's/old/new/g' file              # in-place (macOS)

# awk
awk '{print $1, $3}' file                 # columns 1 and 3
awk -F: '{print $1}' /etc/passwd          # custom delimiter
awk 'NR>=10 && NR<=20' file              # line range
```

### Networking
```bash
curl -s -o /dev/null -w "%{http_code}" URL  # check HTTP status
ping -c 3 hostname                          # connectivity
dig hostname                                # DNS lookup
nc -zv hostname port                        # port check
```

### Disk & files
```bash
df -h                                     # disk usage
du -sh /path/* | sort -h                  # directory sizes
find . -size +100M -type f                # large files
tar -czf archive.tar.gz /path             # compress
tar -xzf archive.tar.gz                   # extract
```

### Rules
- Combine commands with `&&` for sequential, `|` for pipes
- Always use `head` or `tail` to limit output
- Quote variables: `"$var"` not `$var`
