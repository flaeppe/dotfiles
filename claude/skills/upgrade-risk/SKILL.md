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

## Precondition — is this a real upgrade?

Run this before the axes. When the manifest pins a **moving target** rather than
an exact version, the "old version" in the PR title is a tag, not a commit, and
the bump may be a no-op or a downgrade. Moving-target pins look like:

- GitHub Actions on a major tag — `docker/login-action@v4`, `actions/checkout@v7`
- Container images on a floating tag — `:4`, `:4-alpine`, `:latest`
- Any ref that upstream repoints rather than adds to — branch refs, `stable`

Resolve what the pin points at *now* and compare it to the proposed version:

```
gh api repos/<owner>/<repo>/git/ref/tags/<pinned-tag> --jq .object.sha
gh api repos/<owner>/<repo>/git/ref/tags/<proposed-version> --jq .object.sha
```

Most action publishers repoint the major tag at every release, so `@v4` already
resolves to the newest v4.x. If the pin resolves to the same commit as the
proposed version the PR is a no-op; if it resolves to a *later* release the PR
pins us backwards.

Either way: stop, verdict `not a real upgrade`, cite both SHAs, and skip the
axes — there is no blast radius to assess. Say whether the noise is worth a
Dependabot `ignore` rule for minor/patch on that ecosystem. Note that ignore
conditions also suppress security updates, which is usually moot for a moving
pin (a patched release lands under the tag automatically) but matters if the
publisher ever patches without repointing.

Exact pins (`==`, `4.5.2`, a full SHA) skip this section entirely — the bump is
real by construction.

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
Verdict: <not a real upgrade — close it | safe to merge |
          merge after the to-dos | hold — needs prep work>
<one line of why>

Test coverage:   <covered? gaps, with the call sites that lack tests>
Compatibility:   <breaking changes found, pins/notes found — or "none found">
Usage breadth:   <how wide, where; what would make it trustworthy>
Prep work:       <what to do on the current version first — omit if none>

To-do (to make this PR mergeable):
- <concrete, ordered steps: tests to add, refactors, manual checks>
```

On a `not a real upgrade` verdict, drop the four axis lines and the to-do list —
report the two resolved SHAs and the ignore-rule recommendation instead.

If the PR diff or the dependency isn't identifiable from what I gave you, ask
one tight question. Otherwise produce the verdict and state assumptions inline.
