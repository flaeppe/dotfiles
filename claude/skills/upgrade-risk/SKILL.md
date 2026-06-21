---
name: upgrade-risk
description: Assess how safe a dependency-upgrade PR is to merge and what's needed to get comfortable
user-invocable: true
---

Assess the mergeability and blast radius of the dependency-upgrade PR below.
You are assessing one upgrade PR, not deciding whether to upgrade and not
performing the upgrade or merge.

$ARGUMENTS

## Scope

The decision to upgrade is already made — the PR exists. Your job is to judge
how risky merging it is given our actual usage, and to produce the work that
would make it safe. Don't argue for or against the version bump itself, and
don't touch the dependency or the PR.

## Inputs

Identify the dependency, the old → new version, and the manifest/lockfile diff
from the PR. Then assess against our code as it is now.

## Axes

Work all four; each yields findings.

1. **Test coverage of our usage.** Do existing tests actually execute the code
   paths that call into this dependency? Trace from our call sites to tests,
   don't assume a green suite covers them. Where a path is untested, name the
   specific test to add to the PR that pins our real usage before merge.
2. **Compatibility risk.** Check the changelog / release notes across the
   version span for breaking changes, deprecations, and behavioral shifts that
   touch how we use it. Scan our code and comments for version pins or notes
   hinting we're on the current version for a real reason.
3. **Usage breadth.** Map how widely the dependency is used — call sites,
   modules, surface area. The wider the surface, the more verification a merge
   needs. State what evidence would make the upgrade trustworthy at that
   breadth.
4. **Pre-requisite work on the current version.** When the touch surface is
   wide, what should land first — tests to pin behavior, refactors to narrow or
   centralize the usage behind one boundary — before a merge is even attempted.

## Method

- Find call sites before judging anything — grep the dependency's import/package
  name across the repo; breadth and coverage both depend on knowing them.
- Ground every finding in a file/line or a named changelog entry. No claim from
  memory about what changed between versions — read the notes.
- Size the assessment to the blast radius. A leaf dev-dependency with two call
  sites is a one-paragraph verdict; a core runtime library threaded through
  many modules earns the full treatment.

## Output

```
Verdict: <safe to merge | merge after the to-dos | hold — needs prep work>
<one line of why>

Test coverage:   <covered? gaps, with the call sites that lack tests>
Compatibility:   <breaking changes found, pins/notes found — or "none found">
Usage breadth:   <how wide, where; what would make it trustworthy>
Prep work:       <what to do on the current version first — omit if none>

To-do (to make this PR mergeable):
- <concrete, ordered steps: tests to add, refactors, manual checks>
```

If the PR diff or the dependency isn't identifiable from what I gave you, ask
one tight question. Otherwise produce the verdict and state assumptions inline.
