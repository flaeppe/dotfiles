---
name: pr-playbook
description: Generate a review playbook for a pull request
user-invocable: true
---
Study the pull request at $ARGUMENTS in detail. Use the GitHub tools to read the PR description, diff, files changed, existing review comments, and CI status.

Then produce a **review playbook** -- a structured guide for how I should review this PR. Include:

1. **PR Summary** -- What is this PR doing and why? One paragraph.
2. **Key Risk Areas** -- What parts of the change carry the most risk? (data loss, security, correctness, performance)
3. **Architecture Impact** -- How does this PR affect the overall system architecture? Any new dependencies, changed interfaces, or shifted responsibilities between components?
4. **Questions to Ask the Author** -- Anything unclear or suspicious that I should raise.
5. **Testing Checklist** -- What should be tested manually or verified in CI before merging?
6. **Review Order** -- The specific order I should read the files/changes in, and why that order makes sense. For each file or logical group, list the specific things I should verify (edge cases, missing validation, backwards compatibility, etc.). Reference actual file names, function names, and line ranges from the diff.

Be specific to THIS PR -- don't give generic advice. Reference actual file names, function names, and line ranges from the diff.
