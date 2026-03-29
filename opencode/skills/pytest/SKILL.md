name: pytest
description: Use when writing tests in Python with pytest

# pytest

## Overview

pytest-specific patterns and mechanics. This skill covers framework features, not testing philosophy.

**REQUIRED BACKGROUND:** You MUST understand the `test` and `python` skills before using this skill.

## Reference Documentation

For API details not covered here, query via context7:

| Topic | Library |
|-------|---------|
| Configuration, markers, project structure | pytest |
| Async setup | pytest-asyncio |

## Fixtures

### Scopes

```python
# Function scope (default) - runs for each test
@pytest.fixture
def user():
    return {"id": 1, "name": "Alice"}

# Session scope - runs once for entire test session
@pytest.fixture(scope="session")
def db_engine():
    engine = create_engine("postgresql://localhost/test")
    yield engine
    engine.dispose()
```

**When to use:**
- `function` (default): Isolated state per test
- `session`: Expensive setup (DB connections, app bootstrap)
- Avoid `module`/`class` unless clear benefit

### Setup and Teardown

```python
@pytest.fixture
def temp_database():
    db = create_test_database()
    yield db  # Provide to test
    db.drop()  # Cleanup after test
```

### Factory Fixtures

```python
@pytest.fixture
def user_factory(db_session):
    """Factory for creating test users."""
    created = []
    
    def _create(**kwargs):
        user = User(**{"email": f"user{len(created)}@test.com", **kwargs})
        db_session.add(user)
        created.append(user)
        return user
    
    yield _create
    
    # Cleanup all created users
    for user in created:
        db_session.delete(user)
```

### Temporary Files

```python
def test_file_processing(tmp_path):
    """tmp_path provides temporary directory."""
    test_file = tmp_path / "data.json"
    test_file.write_text('{"key": "value"}')
    
    result = process_file(test_file)
    assert result.success
```

## conftest.py Organization

**When to use conftest:**
- Multiple test files need the same fixture (DRY principle)

**Keep in test file:**
- Fixture only used by one test file

**Don't put in conftest:**
- Test data (use `valid_data()` functions in test files)
- Business logic

## Parametrization

For multiple parameters, use a tuple as the first argument:

```python
# Single parameter - string is fine
@pytest.mark.parametrize("status", ["active", "inactive"])

# Multiple parameters - use tuple
@pytest.mark.parametrize(("field", "value", "error"), [
    ("email", "", "Email required"),
    ("balance", -1, "Balance must be positive"),
])
```

**Custom test IDs:** Use `pytest.param(..., id="name")` for descriptive test names:

```python
@pytest.mark.parametrize("amount", [
    pytest.param(0.01, id="small amount"),
    pytest.param(99.99, id="typical amount"),
    pytest.param(9999.99, id="large amount"),
])
def test_can_process_order(amount):
    ...
```

## Async Testing

With `asyncio_mode = "auto"` in pyproject.toml, async test functions and fixtures work without explicit `@pytest.mark.asyncio` markers (they're added automatically). Without this config, add markers manually.

## Assertions

```python
# Exception matching
def test_rejects_invalid_input():
    with pytest.raises(ValueError, match="must be positive"):
        process(-1)

# Exception info access
def test_error_details():
    with pytest.raises(ValidationError) as exc_info:
        validate(bad_data)
    
    assert exc_info.value.field == "email"
```

## Time Testing

Use `freezegun` to prevent flaky time-dependent tests:

```python
from freezegun import freeze_time
from datetime import datetime

@freeze_time("2026-01-15 10:00:00")
def test_token_expiry():
    token = create_token(expires_in_seconds=3600)
    assert token.expires_at == datetime(2026, 1, 15, 11, 0, 0)

@freeze_time("2026-01-15 10:00:00")
def test_time_travel():
    with freeze_time("2026-01-15 10:00:00") as frozen:
        item = create_item()
        
        frozen.move_to("2026-01-20")
        assert item.age_days == 5
```

## Dependencies

Mocking libraries (`unittest.mock`, `pytest-mock`) are forbidden. Design code for dependency injection - fixtures naturally provide test dependencies.

## Testing Outcomes, Not Implementation

Test what the function returns, not how it does it:

```python
# ❌ BAD - testing implementation details
def test_create_user_executes_insert(fake_db, repository):
    user = await repository.create("alice@test.com", "Alice")
    assert "INSERT INTO users" in fake_db.queries[0]  # Knows SQL internals

# ✅ GOOD - testing outcome
def test_can_create_user(fake_db, repository):
    fake_db.will_return([{"id": 1}])
    user = await repository.create("alice@test.com", "Alice")
    assert user.id == 1
    assert user.email == "alice@test.com"
```

Test the interface (Protocol), not the implementation.

## Anti-patterns

| Don't | Why | Do Instead |
|-------|-----|------------|
| `unittest.mock.patch`, `pytest-mock` | Obscures dependencies, hard to trace | Design for DI (see `test` skill) |
| `@pytest.fixture` for `valid_data` | Unnecessary indirection | Plain function |
| Fixtures returning mutable shared state | Test pollution | Return fresh copies |
| `autouse=True` everywhere | Hidden behavior | Explicit fixture usage |
| Missing cleanup in fixtures | Resource leaks | Always use `yield` + cleanup |
| Expensive fixtures without session scope | Slow tests | Use `scope="session"` |
| Docstrings repeating test names | Redundant noise (see `test` skill) | Omit or add non-obvious context |
| Testing implementation details | Couples tests to internals | Test outcomes via Protocol |
| `-> None` return type on test functions | Unnecessary noise | Omit return type |
| `@pytest.mark.parametrize("a,b,c", ...)` | Comma-separated string for multiple params | Use tuple: `(("a", "b", "c"), ...)` |
