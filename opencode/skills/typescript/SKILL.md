---
name: typescript
description: Use when editing TypeScript or JavaScript files - emphasizes strict typing, immutable defaults, and boundary parsing
---

# TypeScript/JavaScript Guidelines

## Core Principles

- **Strict types**: `strict` on; `unknown` over `any`; no implicit `any`
- **Parse at boundaries**: runtime schema (e.g., Zod/Valibot) or manual parse at I/O edges; trust types inside
- **Immutable by default**: `const`, `readonly`, immutable data shapes
- **Discriminated unions**: prefer tagged unions over optional fields
- **Functional-first**: pure functions; keep classes for stateful abstractions only

## Data Shapes and Typing

```ts
// Discriminated union for explicit states
type Loading = { state: 'loading' }
type Ready = { state: 'ready'; data: User[] }
type ErrorState = { state: 'error'; message: string }
type FetchState = Loading | Ready | ErrorState

// readonly collections
const roles: readonly string[] = ['admin', 'user'] as const

// satisfies to keep inference while enforcing shape
const config = {
  retries: 3,
  baseUrl: 'https://api.example.com',
} satisfies {
  retries: number
  baseUrl: string
}

// Prefer interfaces for object shapes, type for unions/aliases
interface User {
  id: string
  email: string
  roles: readonly string[]
}
```

## Boundary Parsing

```ts
import { z } from 'zod'

const UserInput = z.object({
  id: z.string(),
  email: z.string().email(),
  roles: z.array(z.string()).default([]),
})

type UserInput = z.infer<typeof UserInput>

// Parse once at the edge, trust inside
function handleCreateUser(payload: unknown): UserInput {
  return UserInput.parse(payload)
}
```

## Immutability Patterns

```ts
// Avoid mutation of inputs; return new values
function addRole(user: User, role: string): User {
  return { ...user, roles: [...user.roles, role] }
}

// Readonly utility for props/data
type Props = Readonly<{
  title: string
  items: readonly string[]
}>
```

## Error Handling

```ts
class UserNotFoundError extends Error {
  constructor(id: string) {
    super(`User not found: ${id}`)
    this.name = 'UserNotFoundError'
  }
}

function mustFindUser(repo: Repo, id: string): User {
  const user = repo.find(id)
  if (!user) throw new UserNotFoundError(id)
  return user
}
```

## Type Assertions

**Type assertions (`as Type`) override the type checker. This is forbidden.**

### The Only Allowed Assertion: `as const`

```ts
// ✅ Literal inference - the ONLY acceptable use of `as`
const roles = ["admin", "user"] as const
const response = { type: "success" } as const
```

### Forbidden Patterns

```ts
// ❌ FORBIDDEN: Object literal assertions bypass type checking
const user = { name: "Alice" } as User  // Missing fields? TS won't tell you

// ❌ FORBIDDEN: Asserting parsed/external data
const data = JSON.parse(str) as Config  // Parse with schema instead

// ❌ FORBIDDEN: "I know better than the compiler"
const el = document.getElementById('app') as HTMLCanvasElement  // Use instanceof

// ❌ FORBIDDEN: Casting through unknown
const x = foo as unknown as Bar  // Fix the actual type mismatch

// ❌ FORBIDDEN: Even in tests
const mock = {} as SomeType  // Build the real object or use proper mocking

// ❌ FORBIDDEN: Legacy type guard pattern
const obj = value as Record<string, unknown>  // Use 'in' narrowing instead
```

### What To Do Instead

| Instead of | Do this |
|------------|---------|
| `{ x, y } as XY` | Build complete object, let TS verify |
| `JSON.parse(s) as T` | Parse with Zod/Valibot schema |
| `el as HTMLCanvasElement` | `if (el instanceof HTMLCanvasElement)` |
| `x as unknown as Y` | Fix the actual type mismatch |
| `mock as Type` in tests | Construct real object or use typed mock utilities |
| `obj as Record<string, unknown>` | Use `'prop' in obj` for narrowing |

### Rationalization Table

| Excuse | Reality |
|--------|---------|
| "I know the shape is correct" | Then let the compiler verify it. If it can't, your types are wrong. |
| "It's just for convenience" | Convenience now = runtime error later. Build the real object. |
| "The type is too complex to construct" | Simplify the type or use a factory/builder. |
| "It's only in tests" | Tests with wrong shapes give false confidence. Same rules apply. |
| "Third-party types are wrong" | Fix upstream or create proper type guards. Don't paper over it. |
| "I'll fix it later" | You won't. Fix it now. |
| "We know the API is correct" | APIs change. Runtime validation catches this. |
| "I need to access properties" | Use `'prop' in obj` narrowing in modern TypeScript. |

### Red Flags - You're About to Violate This Rule

- Typing `as ` followed by anything other than `const`
- Thinking "the compiler doesn't understand"
- Casting through `unknown` (`x as unknown as Y`)
- "Just this once"

**If you find yourself reaching for `as Type`, stop. The type system is telling you something is wrong. Fix the actual problem.**

## Readability

### No `!!` coercion or `.length` truthiness

These are readability crimes. Say what you mean explicitly.

```ts
// ❌ READABILITY CRIME
!!value        !!!value        !!arr.length
if (items.length)              if (!items?.length)

// ✅ Explicit
value != null   !value          arr.length > 0
if (items.length > 0)          if (items == null || items.length === 0)
```

| Excuse | Reality |
|--------|---------|
| "It's idiomatic JS" | Idiomatic ≠ readable. Say what you mean. |
| "`!!` is well-known" | Known to JS veterans. Opaque to everyone else. |
| "`.length` truthiness is obvious" | `0` being falsy is a language quirk, not a semantic check. |

## Quick Reference

| Prefer | Over |
|--------|------|
| `unknown` | `any` |
| Discriminated unions | Optional property bags |
| `readonly`/`as const` | Mutable arrays/objects |
| Schema parse at boundaries | Ad-hoc inline validation |
| `satisfies` / narrowing / type guards | `as Type` (forbidden except `as const`) |
| Pure functions | Class methods for stateless logic |
| Custom errors | Generic `Error` |
| `value != null` / `arr.length > 0` | `!!value` / `.length` truthiness |
| Explicit comparisons | `!!` coercion |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Implicit `any` | Enable `strict`, annotate inputs/returns |
| Union without tag | Add discriminator (`state`, `kind`) |
| Mutating inputs | Return new object/array |
| Broad `catch (e)` use | Narrow/guard error shape; rethrow unknown |
| `as Foo` assertions | Forbidden. Only `as const` allowed. Use `satisfies`, type guards, or fix the types. |
| `!!value` boolean coercion | Readability crime. Use `value != null`, `arr.length > 0` |
| `.length` in boolean context | Readability crime. Use `items.length > 0`, `items.length === 0` |
