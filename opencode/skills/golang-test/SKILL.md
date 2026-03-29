name: golang-test
description: Use when writing tests in Go with testify

# Go Testing

## Overview

Go testing patterns using testify for assertions and the standard library testing package.

**REQUIRED BACKGROUND:** You MUST understand the `test` and `golang` skills before using this skill.

## Reference Documentation

For API details not covered here, query via context7:

| Topic | Library |
|-------|---------|
| Assertions, mocking, suites | testify |

## Table-Driven Tests

The standard Go testing pattern using `t.Run()` for subtests:

```go
func TestAdd(t *testing.T) {
	tests := []struct {
		name     string
		a, b     int
		expected int
	}{
		{"can add positive numbers", 2, 3, 5},
		{"can add negative numbers", -1, -2, -3},
		{"can add zero values", 0, 0, 0},
		{"can add mixed signs", -1, 1, 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := Add(tt.a, tt.b)
			assert.Equal(t, tt.expected, result)
		})
	}
}
```

**Naming:** Use verb-based names in `t.Run()` - "can add", "rejects invalid", "returns error when".

## Test Helpers

```go
func setupTest(t *testing.T) *Database {
	t.Helper() // Marks this as a helper - errors point to caller

	db := createTestDB()
	
	// Cleanup runs after test completes
	t.Cleanup(func() {
		db.Close()
	})
	
	return db
}

func TestWithTempFile(t *testing.T) {
	// Creates temp directory, auto-cleaned after test
	tmpDir := t.TempDir()
	
	testFile := filepath.Join(tmpDir, "test.txt")
	// ... use testFile
}
```

## Assertions

### assert vs require

```go
import (
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestUser(t *testing.T) {
	user, err := CreateUser("alice@example.com")
	
	// require: Fatal on failure (stops test)
	// Use for preconditions
	require.NoError(t, err)
	require.NotNil(t, user)
	
	// assert: Non-fatal (test continues)
	// Use for actual assertions
	assert.Equal(t, "alice@example.com", user.Email)
	assert.NotEmpty(t, user.ID)
}
```

**Common assertions:**
- `assert.Equal(t, expected, actual)`
- `assert.NoError(t, err)`
- `assert.Nil(t, obj)` / `assert.NotNil(t, obj)`
- `assert.True(t, condition)` / `assert.False(t, condition)`
- `assert.Contains(t, slice, element)`
- `assert.Len(t, slice, expectedLength)`

## Test Doubles

Use interface-based test doubles with dependency injection:

```go
// Define interface
type PaymentGateway interface {
	Charge(amount float64, email string) (string, error)
}

// Production implementation
type StripeGateway struct {
	apiKey string
}

func (s *StripeGateway) Charge(amount float64, email string) (string, error) {
	// Real Stripe API call
}

// Test implementation
type FakePaymentGateway struct {
	Charges []struct {
		Amount float64
		Email  string
	}
	ShouldFail bool
}

func (f *FakePaymentGateway) Charge(amount float64, email string) (string, error) {
	if f.ShouldFail {
		return "", errors.New("payment failed")
	}
	
	f.Charges = append(f.Charges, struct {
		Amount float64
		Email  string
	}{amount, email})
	
	return "txn_123", nil
}

// Test using fake
func TestProcessOrder(t *testing.T) {
	payment := &FakePaymentGateway{}
	service := NewOrderService(payment)
	
	err := service.ProcessOrder(validOrder())
	
	require.NoError(t, err)
	assert.Len(t, payment.Charges, 1)
	assert.Equal(t, 99.99, payment.Charges[0].Amount)
}
```

**Avoid `testify/mock` when possible** - interface-based fakes are clearer and don't require setup/verification boilerplate.

## Anti-patterns

| Don't | Why | Do Instead |
|-------|-----|------------|
| `testify/mock` for everything | Verbose, implicit dependencies | Interface-based fakes with DI |
| `assert` for preconditions | Test continues with bad state | `require` for setup/preconditions |
| Testing private functions | Couples tests to implementation | Test through public API |
| Docstrings repeating test names | Redundant noise (see `test` skill) | Omit or add non-obvious context |
| `time.Sleep()` in tests | Flaky, slow | Use channels or test doubles |
