name: vitest
description: Use when writing tests in TypeScript/JavaScript with Vitest

# Vitest

## Overview

Vitest-specific patterns and mechanics. This skill covers framework features, not testing philosophy.

**REQUIRED BACKGROUND:** You MUST understand the `test` and `typescript` skills before using this skill.

## Reference Documentation

For API details not covered here, query via context7:

| Topic | Library |
|-------|---------|
| Configuration, matchers, mocking API | vitest |

## Test Organization

Use `describe` blocks for grouping, `it` for individual tests:

```typescript
describe("OrderService", () => {
  describe("processOrder", () => {
    it("can process valid order", async () => {
      // test body
    });
    
    it("rejects negative amount", async () => {
      // test body
    });
  });
  
  describe("cancelOrder", () => {
    it("can cancel pending order", async () => {
      // test body
    });
  });
});
```

**Grouping guidelines:**
- Top level: module/class name
- Second level: method/function name
- Don't nest deeper than 2 levels
- Happy paths first within each group

## Test Naming

Adapt the `test` skill's verb-based naming to `it()` syntax:

```typescript
// Happy paths
it("can create user")
it("can get user by id")

// Validation
it("rejects negative amount")
it("rejects invalid email")

// Output
it("returns empty array when no results")
it("returns none for missing user")
```

Omit "should" - the test name describes what the code does, not what it "should" do.

## Setup and Teardown

```typescript
import { beforeEach, afterEach, beforeAll, afterAll } from "vitest";

// Runs before each test in this describe block
beforeEach(async () => {
  await truncateDatabase();
});

// Runs after each test
afterEach(async () => {
  await cleanup();
});

// Runs once before all tests in this describe block
beforeAll(async () => {
  await startServer();
});

// Runs once after all tests
afterAll(async () => {
  await stopServer();
});
```

**When to use:**
- `beforeEach`/`afterEach`: Isolated state per test (default)
- `beforeAll`/`afterAll`: Expensive setup (DB connections, server start)

## Dependencies

Prefer dependency injection over mocking. Design code to accept dependencies, then inject test implementations.

```typescript
// Production
class OrderService {
  constructor(private payment: PaymentGateway, private email: EmailService) {}
  
  async process(order: Order) {
    await this.payment.charge(order.amount);
    await this.email.send(order.customerEmail, "Confirmed");
  }
}

// Test - inject fakes
class FakePaymentGateway implements PaymentGateway {
  charges: Array<{ amount: number }> = [];
  
  async charge(amount: number) {
    this.charges.push({ amount });
  }
}

it("can process order", async () => {
  const payment = new FakePaymentGateway();
  const email = new FakeEmailService();
  const service = new OrderService(payment, email);
  
  await service.process(validOrder());
  
  expect(payment.charges).toHaveLength(1);
});
```

**When `vi.fn()` is acceptable:**
- Testing callbacks/handlers that are passed as arguments
- Creating simple test doubles when a class would be overkill

```typescript
// Acceptable - testing a callback
it("calls onRetry when retry occurs", async () => {
  const onRetry = vi.fn();
  await withRetry(failingFn, { retries: 3, onRetry });
  expect(onRetry).toHaveBeenCalledTimes(2);
});
```

**Avoid `vi.mock()` for business logic** - it makes dependencies implicit. Use DI instead.

## Time Testing

Use `vi.useFakeTimers()` to control time:

```typescript
import { vi } from "vitest";

it("expires token after 1 hour", () => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-01-31 10:00:00"));
  
  const token = createToken({ expiresIn: 3600 });
  
  vi.advanceTimersByTime(3600 * 1000);
  
  expect(token.isExpired()).toBe(true);
  
  vi.useRealTimers();
});
```

## Test Utilities

For complex test suites, consider a `TestHarness` class to centralize:

```typescript
class TestHarness {
  // Seed helpers for database setup
  seed = {
    user: async (overrides?: Partial<User>) => {
      return await db.insert(userTable).values({
        email: "user@example.com",
        ...overrides,
      }).returning();
    },
  };
  
  // Factory functions for valid objects
  factories = {
    validUser: (overrides?: Partial<User>) => ({
      id: "123",
      email: "user@example.com",
      ...overrides,
    }),
  };
  
  // Service overrides for DI
  createApi(overrides?: Partial<ApiClient>) {
    return {
      fetch: () => Promise.resolve({ status: "ok" }),
      ...overrides,
    };
  }
}

const h = new TestHarness();

it("can create user", async () => {
  const user = await h.seed.user({ email: "alice@example.com" });
  expect(user.email).toBe("alice@example.com");
});
```

This pattern keeps test files clean and centralizes common setup logic.

## Anti-patterns

| Don't | Why | Do Instead |
|-------|-----|------------|
| `vi.mock()` for business logic | Makes dependencies implicit | Design for DI |
| Docstrings repeating test names | Redundant noise (see `test` skill) | Omit or add non-obvious context |
| Testing implementation details | Couples tests to internals | Test outcomes |
| Nested describe > 2 levels | Hard to read | Flatten or split files |
| "should" in test names | Verbose, unnecessary | Use verb-based names |
