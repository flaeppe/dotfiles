---
name: python
description: Use when editing Python files - covers type safety, immutability patterns, and functional-first design
---

# Python Guidelines

## Core Principles

**Functional-first, classes when they fit.** Default to functions + data containers. Use classes for stateful abstractions, not as organizational units.

**Parse at boundaries, trust types inside.** Pydantic models validate external input; pass typed instances internally.

**Immutable by default.** Mutation is opt-in, not opt-out.

**No type ignores without approval.** Never use `# type: ignore`, `# pyright: ignore`, or any type-checking suppression without explicit user approval.

**Type hints everywhere.** All function signatures, class attributes, and module-level variables must have type annotations.

**Imports at module top.** Inline imports are forbidden. No exceptions without measured evidence.

The only acceptable reasons for inline imports (and you MUST have profiled evidence, not assumptions):
- Lazy loading a dependency that **measurably** slows startup (profiled, not assumed — "it's a big library" is not evidence)
- Delaying a module with **documented** import-time side effects

Default: put it at the top. If startup becomes a measured problem, move it inline with a comment citing the measurement.

**Circular dependency is NEVER a valid reason for inline imports.** Not for "quick fixes," not for "risk mitigation," not for "complexity." This is a design smell requiring restructuring:
- Move shared types/functions to a third module
- Use `TYPE_CHECKING` blocks for type-only imports
- Redesign the dependency graph

If restructuring seems too complex, **ASK** - don't hide the problem with inline imports. The answer is usually simple.

## Data Containers (in order of preference)

1. **Pydantic `BaseModel`** - when parsing/validation needed (API boundaries, config)
2. **`NamedTuple`** - when types are known, no parsing needed, immutable
3. **`dataclass(frozen=True, kw_only=True)`** - when you need methods or enforced kwargs

```python
# Pydantic at boundaries
from pydantic import BaseModel

class UserInput(BaseModel):
    email: str
    name: str

# NamedTuple for internal domain types
from typing import NamedTuple

class User(NamedTuple):
    id: str
    email: str
    roles: tuple[str, ...]  # tuple, not list - immutable

# Frozen dataclass when kwargs matter or methods needed
from dataclasses import dataclass

@dataclass(frozen=True, slots=True, kw_only=True)
class Config:
    host: str
    port: int = 8080
```

## Type Safety

```python
from typing import Protocol, Final
from collections.abc import Sequence, Mapping  # not typing.*

# Protocol for interfaces (structural subtyping, no inheritance)
class Repository(Protocol):
    def get(self, id: str) -> User | None: ...
    def save(self, user: User) -> None: ...

# Immutable collections
ALLOWED_ROLES: Final = frozenset({"admin", "user", "guest"})
```

## Verification Workflow

Run checks in this order - each catches different issues:

1. **`ruff check --fix .`** - Auto-fix linting issues (instant)
2. **`ruff format .`** - Format all code (instant)
3. **`pyright`** - Type checking
4. **`pytest`** - Tests

Ruff is nearly instant - run it on the entire codebase, not just changed files. Fix lint/format before type checking; some type errors disappear after auto-fixes.

**When to run:**
- Before commits (usually handled by pre-commit hooks)
- Before running pyright
- After any significant code changes

## Boundary Parsing

```python
def create_user(input: UserInput) -> User:  # Pydantic in, domain type out
    return User(id=generate_id(), email=input.email, roles=())

# After parsing, trust the types - no re-validation
def send_welcome(user: User) -> None:
    send_email(user.email, "Welcome!")  # No need to check email format
```

## Custom Exceptions

```python
# ❌ Generic exceptions - risk of accidental catch
raise ValueError("User not found")
raise Exception("Invalid state")

# ✅ Domain-specific exceptions
class UserNotFoundError(Exception):
    def __init__(self, user_id: str) -> None:
        self.user_id = user_id
        super().__init__(f"User not found: {user_id}")

class InvalidStateError(Exception): ...
```

## Inheritance: Almost Never

```python
# ❌ Inheritance for code reuse
class BaseService:
    def log(self, msg: str) -> None: ...

class UserService(BaseService): ...

# ✅ Composition
class UserService:
    def __init__(self, logger: Logger) -> None:
        self._logger = logger

# ❌ ABC for interfaces
from abc import ABC, abstractmethod
class Repository(ABC): ...

# ✅ Protocol (structural, no inheritance needed)
class Repository(Protocol): ...
```

**When inheritance is acceptable:** Framework requirements (Django models, Exception subclasses).

## Quick Reference

| Prefer | Over |
|--------|------|
| `NamedTuple` | `dataclass` (when no methods needed) |
| Pydantic `BaseModel` | manual validation |
| `Protocol` | `ABC` |
| `tuple[T, ...]` | `list[T]` (for immutable sequences) |
| `frozenset` | `set` |
| `Mapping` | `dict` (in signatures) |
| `Sequence` | `list` (in signatures) |
| `defaultdict(list)` | `dict.setdefault(k, [])` |
| Functions | Methods (when no state) |
| Composition | Inheritance |
| Custom exceptions | Built-in exceptions |
| `ruff check --fix . && ruff format .` | Manual linting (before pyright) |
| Top-level imports | Inline imports (circular deps = restructure or ask, never inline) |
| `if not x and not y and not z` | `if not (x or y or z)` (explicit conditions easier to parse) |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| `list` in NamedTuple | Use `tuple[T, ...]` - lists are mutable |
| Re-validating parsed data | Trust the types after boundary parsing |
| `from typing import List, Dict` | Use `list`, `dict` directly (3.9+) |
| Class with only `__init__` and methods | Probably should be functions |
| Inheriting to share code | Inject shared dependency instead |
| `raise ValueError` for domain errors | Create custom exception class |
| `# type: ignore` or `# pyright: ignore` | Ask for explicit approval first - suppressing types hides bugs |
| Untyped function signature | Add return type and parameter types - no exceptions |
| Running pyright before ruff | Run `ruff check --fix . && ruff format .` first - fixes may resolve type errors |
| `# Import here to avoid circular dependency` | STOP. Never allowed. Restructure or ASK where to move code - the fix is usually simple |
| Inline import without reason | Move to top unless lazy loading or delaying module side effects |
| `d.setdefault(k, []).append(v)` in loop | Use `defaultdict(list)` - simpler and faster |
| `if not (x or y or z)` | Use `if not x and not y and not z` - explicit conditions require less mental parsing |
