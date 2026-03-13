---
name: file-ops
description: File operations - find, search, edit, compare, bulk operations
triggers: [find file, search file, grep, replace, edit file, compare, diff file, rename, move, copy, file size, count lines]
---

## File Operations

### Search content
```bash
grep -rn "pattern" /path --include="*.ex" | head -20
grep -rn "pattern" /path --include="*.{ts,js}" | head -20
```
Or use the `search_files` tool with regex patterns.

### Find files
```bash
find /path -name "*.ex" -type f | head -30
find /path -name "*.test.*" -type f
find /path -newer reference_file -type f         # modified after
find /path -size +1M -type f                     # large files
find /path -mtime -1 -type f                     # modified in last day
```

### File info
```bash
wc -l file                          # line count
wc -l /path/**/*.ex                 # lines per file
du -sh file                         # file size
file filename                       # file type
stat filename                       # full metadata
```

### Compare
```bash
diff file1 file2
diff -u file1 file2                 # unified diff
diff -r dir1 dir2                   # recursive directory diff
```

### Read sections
```bash
head -50 file                       # first 50 lines
tail -50 file                       # last 50 lines
sed -n '10,30p' file                # lines 10-30
```

### Bulk operations — always confirm with user before:
```bash
find . -name "*.bak" -type f        # list first, don't delete
```

### Rules
- NEVER delete files without user confirmation
- NEVER overwrite files without reading them first
- Use `read_file` tool for full content, bash for quick peeks
