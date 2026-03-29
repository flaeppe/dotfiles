name: test
description: Use when writing, reviewing, structuring, or updating tests in any language - covers test design philosophy, naming, organization, the valid_data pattern, and updating repeated test code (assertions, setup, mocks)

# Testing

## Overview

**Readability is religion.** Tests are documentation. Optimize for reading, not writing.

The art of testing lies in structure and clarity: valid data → minimal modification → execute → assert outcome. Keep test bodies small. Extract complexity into reusable patterns.

## Core Principles

1. **No mocking libraries** - Use dependency injection and test doubles (fakes, stubs). Mock libraries are forbidden.

2. **No log assertions** - Logs are side effects. Assert on business logic outcomes. This is always possible.

3. **Broader tests preferred** - Cross-boundary tests cover more ground with less knowledge of internals. Happy paths on these cover significant ground.

4. **Minimal test bodies** - If setup is complex, extract it. The test body should read: valid → modify → run → assert.

5. **Tests shouldn't know internals** - Focus on input → expected outcome. The sweet spot is testing behavior without coupling to implementation.

6. **No redundant coverage** - If a cross-boundary test covers it, cut the unit test. When one change breaks 15 tests, there's overlap.

7. **Breaking tests should make sense** - A failing test should point to what broke, not create noise.

## Naming Convention

```
test_<verb>_<what>[_<condition>]
```

**Verbs (by category):**

| Category | Verbs | Example |
|----------|-------|---------|
| Happy path | `can_` | `test_can_parse_valid_input` |
| Output | `returns_` | `test_returns_error_for_invalid_id` |
| Validation | `rejects_`, `errors_on_` | `test_rejects_negative_balance` |
| Rules | `allows_`, `requires_` | `test_requires_email_for_signup` |
| Behavior | `stops_`, `does_not_` | `test_does_not_retry_on_auth_failure` |

**The name should tell you what the test verifies without reading the body.**

## The valid_data Pattern

Create a function that returns a **complete, valid payload** for the domain:

```python
def valid_data() -> dict[str, Any]:
    return {
        "email": "user@example.com",
        "balance": 1000,
        "status": "active",
        # ... complete valid state
    }
```

**Boundary tests modify minimally:**

```python
def test_rejects_negative_balance():
    data = valid_data()
    data["balance"] = -1  # Single modification
    
    result = process(data)
    
    assert result.rejected
    assert result.reason == "Balance must be positive"
```

This pattern makes tests self-documenting: you see exactly what condition is being tested.

## Test Body Structure

```
1. Arrange  - Start with valid data, modify minimally
2. Act      - Execute the thing under test
3. Assert   - Verify outcome (few assertions)
```

Keep assertions focused:
- Assert what the test is verifying, not prerequisites
- Avoid asserting intermediate state unless that's what you're testing
- Multiple assertions are fine when verifying a complete object (happy path)
- Fewer assertions = clearer failure messages

## Test Organization

Group tests by **what they protect**, not by test type.

**The cohesion test:** If one business rule changes, which tests should break? Those tests belong together.

**Signs of poor organization:**
- One change breaks tests in many unrelated directories
- You can't find tests for a feature without searching
- Duplicate coverage across locations
- Same domain scattered by "unit" vs "integration"

**Within a test file:**
1. Happy path(s) first
2. Boundary/validation tests
3. Error handling tests
4. Edge cases

## Parametrization

Use parametrization when:
- Input variations are small and readable
- Test logic is identical across cases
- You can generate meaningful test IDs
- Testing the same rule with different inputs

Prefer separate test functions when:
- Input data is large or complex
- Each case needs different setup or assertions
- Error messages differ significantly between cases
- IDs would be meaningless indexes

**Always generate descriptive IDs.** `test_validates[1]` tells you nothing. `test_validates[missing_email]` tells you everything. If no good description exists, an index is acceptable.

**Example of when to parametrize:**

```python
@pytest.mark.parametrize("status", ["active", "inactive", "suspended"])
def test_can_create_user_with_status(status):
    data = valid_data()
    data["status"] = status
    user = create_user(**data)
    assert user.status == status
```

**Example of when NOT to parametrize:**

```python
# Different assertion patterns - keep separate
def test_returns_user_for_valid_id():
    result = get_user(valid_id)
    assert result.email == "user@example.com"
    assert result.status == "active"

def test_returns_none_for_missing_id():
    result = get_user(missing_id)
    assert result is None
```

```python
# Complex input that doesn't fit in a parameter list - keep separate
def test_can_process_nested_order():
    data = valid_data()
    data["items"] = [
        {"sku": "A1", "quantity": 2, "modifiers": [...]},
        {"sku": "B2", "quantity": 1, "modifiers": [...]},
    ]
    result = process_order(data)
    assert result.total == expected_total
```

## Updating Repeated Test Code

When updating assertions, setup patterns, or mocks that repeat across multiple tests:

**Verify the change on one test before applying to all tests.**

```
1. Update ONE test
2. Run that single test to verify correctness
3. Once verified, apply to remaining tests (replaceAll or individual edits)
```

**Why:** Updating all tests without verification creates wasteful iteration loops. If the change is wrong, you update all N tests, run all N tests, discover the error, fix all N tests again, repeat. Verifying one test first catches errors in 5 seconds instead of multiple full suite runs.

**How to apply after verification:**
- **Identical changes:** Use `replaceAll` to update remaining tests in one operation
- **Similar but different:** Edit remaining tests individually (they may have slight variations)

The key is **verify first, then apply broadly** - not apply broadly, then discover issues.

**Common rationalizations to avoid:**

| Excuse | Reality |
|--------|---------|
| "More efficient to update all at once" | Only if correct. Unverified batch updates waste more time. |
| "Simple string replacement" | Simple changes can still be wrong. Verify first. |
| "All tests are the same" | Verify that assumption with one test first. |
| "Just updating string literals" | String literals can be wrong. Verify with one test. |
| "No skill needed for mechanical changes" | This IS the skill. Follow it. |
| "I already verified it manually" | Run one test to confirm. Takes 5 seconds. |

**Example:**

```python
# You need to update 8 tests from:
assert result.status == "success"
# To:
assert result.state == "completed"

# ❌ DON'T: Update all 8 with replaceAll, run full suite, discover field is still "status", 
#           fix all 8 again, run full suite again, repeat
# ✅ DO: Update test_can_process_credit_card, run it, verify it passes, 
#        THEN use replaceAll for the remaining 7 tests
```

## Test Infrastructure Awareness

When writing tests, consider the full suite:

- **Data loading**: Prefer programmatic fixtures over large JSON files. If external data is needed, structure for selective loading.
- **Database setup**: Design for parallelization. Tests should not share mutable state.
- **Collection speed**: Structure so the runner collects quickly. Avoid dynamic test generation at import time.
- **Sub-suites**: Organize so subsets can run independently (by domain, by speed, by integration level).

Implementation is framework-specific—see language test skills.

## Anti-patterns

| Don't | Why |
|-------|-----|
| Docstrings repeating test names | Redundant noise |
| Mock libraries | Use DI + test doubles instead |
| Asserting on logs | Assert on business outcomes |
| Swapping integration for unit tests | Don't trade coverage for control |
| Tests knowing implementation details | Couples tests to code structure |
| Large JSON fixture files | Hard to understand, maintain, selectively load |
| Removing broader tests for narrow ones | Loses coverage, increases noise |
