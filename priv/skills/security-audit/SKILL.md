---
name: security-audit
description: Security audit, vulnerability scanning, secure coding practices
triggers: [security, vulnerability, audit, cve, injection, xss, csrf, auth, authentication, authorization, secret, password, token leak]
---

## Security Audit

### Code scan checklist
1. **Injection** — SQL, command, LDAP, XPath
   ```bash
   grep -rn "System.cmd\|:os.cmd\|Port.open" --include="*.ex" | head -20
   grep -rn "Repo.query.*#{" --include="*.ex" | head -20   # SQL injection
   grep -rn "eval\|exec\|spawn" --include="*.js" | head -20
   ```

2. **Secrets in code**
   ```bash
   grep -rn "password\|secret\|api_key\|token\|private_key" --include="*.{ex,js,ts,py,env}" | grep -v node_modules | grep -v _build | head -20
   ```

3. **Hardcoded credentials**
   ```bash
   grep -rn "sk-\|sk_live\|AKIA\|ghp_\|gho_" . | grep -v _build | grep -v deps | head -10
   ```

4. **Insecure dependencies**
   ```bash
   # Elixir
   mix deps.audit 2>/dev/null || mix hex.audit
   # Node.js
   npm audit
   # Python
   pip-audit 2>/dev/null || safety check
   ```

5. **File permissions**
   ```bash
   find . -name "*.pem" -o -name "*.key" -o -name ".env*" | head -10
   ```

### Common vulnerabilities
| Issue | Check |
|-------|-------|
| SQL Injection | String interpolation in queries |
| XSS | Unescaped user input in HTML |
| CSRF | Missing CSRF tokens in forms |
| Command Injection | User input in shell commands |
| Path Traversal | `../` in file paths |
| Insecure Deserialization | `Marshal.load`, `pickle.loads`, `:erlang.binary_to_term` |
| Exposed secrets | `.env`, API keys in code |

### Output format
```
🔴 CRITICAL: SQL injection in lib/queries.ex:42
   Code: Repo.query("SELECT * FROM users WHERE name = '#{name}'")
   Fix:  Repo.query("SELECT * FROM users WHERE name = $1", [name])
```
