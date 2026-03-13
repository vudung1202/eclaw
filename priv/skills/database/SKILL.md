---
name: database
description: Database operations - PostgreSQL, MySQL, SQLite, Ecto migrations
triggers: [database, db, postgres, postgresql, mysql, sqlite, sql, query, migration, schema, table, ecto, repo]
---

## Database Operations

### PostgreSQL
```bash
psql -U user -d dbname -c "SELECT * FROM table LIMIT 20"
psql -l                                   # list databases
psql -d dbname -c "\dt"                   # list tables
psql -d dbname -c "\d table_name"         # describe table
psql -d dbname -c "\di"                   # list indexes
psql -d dbname -c "SELECT count(*) FROM table"
```

### MySQL
```bash
mysql -u user -p dbname -e "SHOW TABLES"
mysql -u user -p dbname -e "DESCRIBE table_name"
mysql -u user -p dbname -e "SELECT * FROM table LIMIT 20"
```

### Ecto (Elixir)
```bash
mix ecto.create
mix ecto.migrate
mix ecto.rollback
mix ecto.rollback --step 3
mix ecto.migrations                       # migration status
mix ecto.gen.migration add_users_table
mix ecto.dump                             # dump schema
mix ecto.reset                            # drop + create + migrate
```

### Query safety rules
- ALWAYS add `LIMIT` to SELECT queries
- NEVER run `DROP` or `DELETE` without WHERE and user confirmation
- Use `EXPLAIN ANALYZE` before optimizing
- Use parameterized queries, never string interpolation for values
- Backup before destructive migrations

### Performance
```sql
EXPLAIN ANALYZE SELECT ...;
SELECT pg_size_pretty(pg_total_relation_size('table_name'));
SELECT * FROM pg_stat_activity WHERE state = 'active';
```
