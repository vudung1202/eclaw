---
name: data-analysis
description: Analyze data from files, logs, CSVs, JSON
triggers: [analyze, data, csv, json, parse, statistics, count, aggregate, sort, filter, log analysis, awk, jq]
---

## Data Analysis

### CSV processing
```bash
# View structure
head -5 data.csv
wc -l data.csv                            # row count

# Column extraction
cut -d',' -f1,3 data.csv | head -10       # columns 1 and 3
awk -F',' '{print $1, $3}' data.csv | head -10

# Filter rows
awk -F',' '$3 > 100' data.csv | head -10  # where column 3 > 100
grep "pattern" data.csv | head -10

# Sort
sort -t',' -k3 -n data.csv | tail -10     # sort by column 3 numeric

# Unique values
cut -d',' -f2 data.csv | sort -u          # unique values in column 2
cut -d',' -f2 data.csv | sort | uniq -c | sort -rn | head -10  # frequency
```

### JSON processing with jq
```bash
# Pretty print
cat data.json | jq '.'

# Extract fields
cat data.json | jq '.[] | {name, age}'

# Filter
cat data.json | jq '.[] | select(.age > 30)'

# Count
cat data.json | jq 'length'

# Group & aggregate
cat data.json | jq 'group_by(.category) | map({key: .[0].category, count: length})'
```

### Log analysis
```bash
# Error frequency
grep -c "ERROR" app.log
grep "ERROR" app.log | awk '{print $4}' | sort | uniq -c | sort -rn | head -10

# Time range
awk '$0 >= "2026-03-13 14:00" && $0 <= "2026-03-13 15:00"' app.log

# Response times
grep "completed in" app.log | awk '{print $NF}' | sort -n | tail -10  # slowest
```

### Quick statistics
```bash
# Sum, avg, min, max from a column of numbers
awk '{sum+=$1; n++} END {print "count:", n, "sum:", sum, "avg:", sum/n}' numbers.txt
sort -n numbers.txt | head -1              # min
sort -n numbers.txt | tail -1              # max
```
