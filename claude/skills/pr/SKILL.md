---
name: pr
description: Create a pull request with well-structured title and description
user-invocable: true
---
Ensure branch is pushed to remote, then analyze ALL commits on the branch (not just latest) and create PR with gh pr create.

Title format:
- Use conventional commit format: type(scope): description
- Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore
- Keep concise but descriptive

Description format:
- ## Summary section with 2-4 bullet points
- Explain the WHY, not just the WHAT
- Reference related issues/tickets
- Note any breaking changes or migration steps
- Include testing notes if relevant

Use HEREDOC for multi-line body:
gh pr create --title "type(scope): description" --body "$(cat <<'EOF'
## Summary
- Point 1
- Point 2
EOF
)"

$ARGUMENTS
