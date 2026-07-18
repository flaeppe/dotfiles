# deps-expert

A senior dependency-graph reviewer. It sees a codebase as **one graph of named
items** — functions, types, modules, packages — connected by edges (imports,
calls, type references, throws), and it audits that graph with a single question:
**who is aware of what, and why?**

This README is the concept map. The runnable discipline is `SKILL.md`; the
design contract (invariants, size budget, rehaul bar) is `SPEC.md`.

## The core idea

Most "architecture" problems are really **graph** problems. A layering
violation, a dependency cycle, a leaky abstraction, a 3rd-party SDK smeared
across business logic — each is an *edge that should not exist*, or points the
wrong way. So the skill does not carry a grab-bag of architectural opinions. It
carries one model (the graph) and one lens (awareness), and everything else is
derived.

- **One graph, every altitude.** The reasoning that decides "should this
  function call that one" is the *same* reasoning that decides "should this
  service know about that 3rd party." Only the zoom level changes:
  function→function, type→type, module→module, codebase→package. Name the
  altitude when you report; apply the same lens regardless.
- **Awareness is the lens.** `from` is aware of `to` when it mentions `to` by
  name — an import, a type reference, a call, a `throw`. That mention *is* the
  dependency, however indirect the runtime path. For every edge: *is `from`
  aware of `to`, and should it be?* Most violations reduce to "this should not
  be aware of that," and every finding is phrased that way.
- **Names draw the lines.** The graph exists only because items have names.
  `chargeStripeCustomer` in a business module has named itself into the wrong
  layer; `chargeCustomer` belongs to the domain and the Stripe-aware
  implementation to an adapter beneath it. Fast diagnostic: *if you renamed it,
  where would it move?* If the natural name pulls it into another module, it is
  misplaced now.

## The normative shape

Before measuring, the skill states the shape the graph *should* take, then
measures against it. The template:

```
3rd-party schemas → integrations / persistence / translators
                          ↑
                  domain types & business logic
                          ↑
                  boundary layers (HTTP handlers, consumers, CLI)
```

Edges point from less-stable to more-stable (Stable Dependencies Principle). Two
symmetric leak directions matter:

- **Nothing higher is aware of 3rd-party specifics.** A vendor's types stay at
  their boundary; business logic speaks its own domain vocabulary.
- **Nothing lower is aware of the boundary's protocol.** Transport error
  classes, request/response objects, resolver context, status codes are
  *boundary* vocabulary. A domain or service module that imports or throws one
  (e.g. a GraphQL error class thrown in a service) has drawn an upward edge onto
  the protocol — the fix is a domain-owned error the boundary translates.

## Two modes

- **Diff-Scoped** (default when a diff has source changes) — audit only the new
  edges the diff introduces. Speed first: is each new awareness appropriate?
- **Full Audit** (clean tree, or an explicit target) — derive the whole graph
  and run every detection rule. Used before refactors or when the graph rotted.

## Detection rules at a glance

Every finding cites the rule it breaks. Grouped by severity in the output.

| # | Rule | Catches |
|---|------|---------|
| 1 | Cycles | Strongly-connected components — the module graph must be a DAG |
| 2 | Layer Violations | Upward edges — boundary handlers or protocol/framework types pulled into domain code |
| 3 | Foreign-Error Throws | Throwing an error owned by another package/domain node (a module's own `./errors` is fine) |
| 4 | Awareness Leaks | A high module naming a low (usually 3rd-party) concept outside the integration layer |
| 5 | 3rd-Party Scatter | One vendor imported directly from many business modules instead of one integration point |
| 6 | Cross-Context Coupling | Two feature domains depending on each other directly, not via a shared kernel/event/API |
| 7 | Co-Change Without Import | Modules that always change together but don't reference each other — hidden coupling |
| 8 | Fan-Out Hubs | A module importing many others — often misplaced responsibility |
| 9 | Stable Abstractions | High-in-degree modules that are highly concrete (SAP) |

Rules 2 and 3 overlap on the canonical case — a protocol error thrown in a
service — but cover different ground: Rule 2 is about *direction* (an upward
edge onto the boundary), Rule 3 about *ownership* (throwing any foreign node's
error, even sideways between peers).

## Design stance (what it does not do)

- **Analysis only.** It produces findings and corrected-graph shapes. It never
  rewrites code — refactoring is a separate step.
- **Concrete or nothing.** Every finding is a named edge in a named module, not
  an abstract plea to "reduce coupling." If everything looks wrong, the bar is
  too low.
- **No speculative abstractions.** It proposes an interface only when the
  abstraction resolves a *named* violation. Adding indirection "for flexibility"
  with no current violation is over-engineering, and the skill calls that out
  rather than adding it.
- **Graph-first tooling.** It derives the graph from `codebase-memory-mcp`
  (`get_architecture`, `search_graph`, `trace_path`, `query_graph`); text grep
  is the fallback for what the graph misses (string imports, dynamic dispatch).

## Anatomy

| File | Role |
|---|---|
| `SKILL.md` | the runnable discipline (loaded at runtime) |
| `SPEC.md` | design contract: purpose, invariants, size budget, rehaul threshold |
| `README.md` | this concept map |

History lives in git — one commit per change, the *why* in its message. There is
no changelog file here.
