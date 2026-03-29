---
name: golang
description: Use when editing Go code - emphasizes small interfaces, explicit errors, and safe concurrency
---

# Go Guidelines

## Core Principles

- **Small interfaces**: accept interfaces, return structs; define minimal method sets
- **Explicit errors**: return errors with context; no panics in normal flow
- **Context first**: first param `ctx context.Context`; propagate cancellations
- **Concurrency safety**: prefer channels or mutexes with clear ownership; avoid sharing mutable maps without sync
- **Zero-value friendly**: types should work when zero-initialized

## Interfaces and Errors

```go
type User struct {
    ID    string
    Email string
    Roles []string
}

// Small interface
type UserRepo interface {
    Get(ctx context.Context, id string) (User, error)
    Save(ctx context.Context, u User) error
}

// Error with context
var ErrUserNotFound = errors.New("user not found")

func (r *Repo) Get(ctx context.Context, id string) (User, error) {
    u, ok := r.data[id]
    if !ok {
        return User{}, fmt.Errorf("get user %s: %w", id, ErrUserNotFound)
    }
    return u, nil
}
```

## Concurrency Patterns

```go
// Prefer channels for ownership transfer
jobs := make(chan Job)
go func() {
    defer close(jobs)
    for _, j := range source {
        jobs <- j
    }
}()

// WaitGroup + contexts for cancellation
var wg sync.WaitGroup
ctx, cancel := context.WithCancel(parent)
defer cancel()

wg.Add(1)
go func() {
    defer wg.Done()
    for {
        select {
        case <-ctx.Done():
            return
        case j, ok := <-jobs:
            if !ok {
                return
            }
            handle(j)
        }
    }
}()

wg.Wait()
```

## Immutability and Copies

```go
// Avoid sharing mutable slices/maps across goroutines
rolesCopy := append([]string(nil), u.Roles...)

// Prefer returning copies when exposing internal state
func (u User) RoleNames() []string {
    return append([]string(nil), u.Roles...)
}
```

## Testing (Table-Driven)

```go
func TestParseUser(t *testing.T) {
    tests := []struct {
        name    string
        input   string
        want    User
        wantErr error
    }{
        {"ok", "id,email", User{ID: "id", Email: "email"}, nil},
        {"bad", "", User{}, ErrInvalidUser},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := ParseUser(tt.input)
            if !errors.Is(err, tt.wantErr) {
                t.Fatalf("err = %v, want %v", err, tt.wantErr)
            }
            if diff := cmp.Diff(tt.want, got); diff != "" {
                t.Fatalf("diff: %s", diff)
            }
        })
    }
}
```

## Quick Reference

| Prefer | Over |
|--------|------|
| Small interfaces | Fat interfaces |
| Return structs | Return interfaces |
| `ctx` as first param | No context / buried context |
| `error` with `%w` wrapping | `panic` / bare errors |
| Channels or mutex with ownership | Shared mutable maps without sync |
| Copy before sharing | Sharing slices/maps across goroutines |
| Table-driven tests | Ad-hoc per-test code |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Ignoring `ctx` | Accept and propagate `context.Context` |
| Returning interfaces | Return structs; accept interfaces |
| Panics in flow | Return errors; panic only for programmer bugs |
| Sharing mutable state | Use channels/locks; copy slices/maps |
| No error wrapping | Wrap with context using `%w` |
