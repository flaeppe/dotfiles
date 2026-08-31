---
name: run-tests
description: Run tests with coverage
user-invocable: true
model: sonnet
context: fork
---
Run the full test suite with coverage report and show any failures.
Focus on the failing tests and suggest fixes.

Report back only what the caller needs: which tests failed, the assertion or
error for each, and the suggested fix. The suite's own output stays here.
