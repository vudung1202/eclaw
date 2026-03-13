---
name: testing
description: Run tests, write tests, debug test failures
triggers: [test, testing, spec, unit test, integration test, test failure, coverage, mock, assert, exunit, jest, pytest]
---

## Testing

### Run tests
```bash
# Elixir
mix test
mix test test/specific_test.exs
mix test test/specific_test.exs:42    # specific line
mix test --failed                     # rerun failed
mix test --trace                      # verbose output
mix test --cover                      # coverage report

# Node.js
npm test
npx jest --verbose
npx jest path/to/test.spec.ts
npx jest --coverage

# Python
pytest
pytest test_file.py::test_name -v
pytest --tb=short
pytest --cov
```

### Write tests — checklist
- Happy path (expected input → expected output)
- Edge cases (empty, nil, zero, negative, unicode, very large)
- Error cases (invalid input, missing data, network failure)
- Boundary values (min, max, off-by-one)

### Elixir ExUnit patterns
```elixir
describe "function_name/arity" do
  test "describes the expected behavior" do
    assert result == expected
  end

  test "handles edge case" do
    assert {:error, _} = MyModule.function(bad_input)
  end
end
```

### Debug test failures
1. Read the error message carefully — file, line, expected vs actual
2. Run the single failing test with `--trace`
3. Add `IO.inspect(value, label: "debug")` to trace data flow
4. Check test setup — missing fixtures, stale state, ordering dependency

### Rules
- Tests should be independent — no shared mutable state
- Test behavior, not implementation
- Use descriptive test names that explain the scenario
