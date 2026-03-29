name: jest
description: Use when writing tests in TypeScript/JavaScript with Jest

# Jest

## Overview

Jest and Vitest are API-compatible. Follow the `vitest` skill for all patterns and principles.

**REQUIRED BACKGROUND:** You MUST understand the `test`, `typescript`, and `vitest` skills before using this skill.

## API Mapping

The only difference between Jest and Vitest is the API namespace:

| Vitest | Jest |
|--------|------|
| `vi.fn()` | `jest.fn()` |
| `vi.mock()` | `jest.mock()` |
| `vi.spyOn()` | `jest.spyOn()` |
| `vi.useFakeTimers()` | `jest.useFakeTimers()` |
| `vi.useRealTimers()` | `jest.useRealTimers()` |
| `vi.advanceTimersByTime()` | `jest.advanceTimersByTime()` |
| `vi.setSystemTime()` | `jest.setSystemTime()` |

Everything else (`describe`, `it`, `expect`, `beforeEach`, etc.) is identical.

## Configuration

For Jest-specific configuration and APIs, query Jest docs via context7.
