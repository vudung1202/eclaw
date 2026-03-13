---
name: csv-json
description: Convert and transform between CSV, JSON, and other data formats
triggers: [csv, json, yaml, toml, xml, convert, transform, parse, serialize, format, jq, yq]
---

## CSV & JSON Processing

### JSON with jq
```bash
# Pretty print
cat data.json | jq '.'

# Extract field
cat data.json | jq '.name'
cat data.json | jq '.users[0].email'

# Array operations
cat data.json | jq '.[] | .name'                    # all names
cat data.json | jq '[.[] | select(.age > 30)]'      # filter
cat data.json | jq 'length'                          # count
cat data.json | jq 'sort_by(.name)'                  # sort
cat data.json | jq '[.[] | .price] | add'            # sum

# Transform
cat data.json | jq '.[] | {id, full_name: .name}'   # reshape
cat data.json | jq 'group_by(.category) | map({key: .[0].category, count: length})'

# Create JSON
jq -n '{name: "test", value: 42}'
jq -n --arg name "test" '{name: $name}'
```

### CSV processing
```bash
# View structure
head -5 data.csv
wc -l data.csv

# Extract columns
cut -d',' -f1,3 data.csv | head -10
awk -F',' '{print $1, $3}' data.csv | head -10

# Filter
awk -F',' '$3 > 100' data.csv
grep "pattern" data.csv

# Sort by column
sort -t',' -k3 -n data.csv | tail -10

# Unique + frequency
cut -d',' -f2 data.csv | sort | uniq -c | sort -rn | head -10
```

### Conversions
```bash
# JSON → CSV (with jq)
cat data.json | jq -r '.[] | [.name, .email, .age] | @csv'

# CSV → JSON (with jq)
# First line as headers
cat data.csv | python3 -c "import csv,json,sys; print(json.dumps([dict(r) for r in csv.DictReader(sys.stdin)]))" | jq '.'

# YAML → JSON
cat data.yaml | python3 -c "import yaml,json,sys; print(json.dumps(yaml.safe_load(sys.stdin)))"

# JSON → YAML
cat data.json | python3 -c "import yaml,json,sys; print(yaml.dump(json.load(sys.stdin)))"
```

### Elixir
```elixir
# JSON
Jason.encode!(%{name: "test"})
Jason.decode!(~s({"name": "test"}))

# CSV (with NimbleCSV)
NimbleCSV.RFC4180.parse_string(csv_string)
```

### Rules
- Use `jq` for JSON processing in bash
- Use `awk`/`cut` for simple CSV operations
- For complex CSV, consider Python one-liners
- Always pipe through `head` to limit output
- Validate JSON with `jq '.'` before processing
