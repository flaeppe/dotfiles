---
name: codebase-memory
description: Structural code queries through the codebase knowledge graph -- architecture, what functions exist, callers and callees, call chains, dependencies, impact analysis, dead code, high fan-out, refactor candidates, and search_graph or Cypher syntax.
---

# Codebase Memory — Knowledge Graph Tools

Graph tools return precise structural results in ~500 tokens vs ~80K for grep.

## Quick Decision Matrix

| Question | Tool call |
|----------|----------|
| Who calls X? | `trace_path(direction="inbound")` |
| What does X call? | `trace_path(direction="outbound")` |
| Full call context | `trace_path(direction="both")` |
| Find by name pattern | `search_graph(name_pattern="...")` |
| Dead code | `search_graph(max_degree=0, exclude_entry_points=true)` |
| Cross-service edges | `query_graph` with Cypher |
| Impact of local changes | `detect_changes()` |
| Risk-classified trace | `trace_path(risk_labels=true)` |
| Text search | `search_code` or Grep |

## Exploration Workflow
1. `list_projects` — check if project is indexed
2. `get_graph_schema` — understand node/edge types
3. `search_graph(label="Function", name_pattern=".*Pattern.*")` — find code
4. `get_code_snippet(qualified_name="project.path.FuncName")` — read source

## Tracing Workflow
1. `search_graph(name_pattern=".*FuncName.*")` — discover exact name
2. `trace_path(function_name="FuncName", direction="both", depth=3)` — trace
3. `detect_changes()` — map git diff to affected symbols

## Quality Analysis
- Dead code: `search_graph(max_degree=0, exclude_entry_points=true)`
- High fan-out: `query_graph` — `MATCH (a)-[:CALLS]->(b) RETURN a.name, count(b) AS fan_out ORDER BY fan_out DESC LIMIT 20`
- High fan-in: `query_graph` — `MATCH (a)-[:CALLS]->(b) RETURN b.name, count(a) AS fan_in ORDER BY fan_in DESC LIMIT 20`

## 17 MCP Tools
`index_repository`, `index_status`, `check_index_coverage`, `list_projects`,
`delete_project`, `search_graph`, `search_code`, `trace_path`,
`detect_changes`, `compare_graphs`, `query_graph`, `get_graph_schema`,
`get_code_snippet`, `get_file_outline`, `get_architecture`, `manage_adr`,
`ingest_traces`

## Edge Types
CALLS, CALL_REFERENCE, HTTP_CALLS, ASYNC_CALLS, IMPORTS, DEFINES,
DEFINES_METHOD, HANDLES, IMPLEMENTS, OVERRIDE, USAGE, FILE_CHANGES_WITH,
CONTAINS_FILE, CONTAINS_FOLDER, CONTAINS_PACKAGE

`CALLS` is a direct invocation. A function passed by value as a callback
(`items.map(handler)`) is `CALL_REFERENCE`; match both for complete callers:
`[:CALLS|CALL_REFERENCE]`.

## Cypher Examples (for query_graph)
```
MATCH (a)-[r:HTTP_CALLS]->(b) RETURN a.name, b.name, r.url_path, r.confidence LIMIT 20
MATCH (f:Function) WHERE f.name =~ '.*Handler.*' RETURN f.name, f.file_path
MATCH (a)-[r:CALLS]->(b) WHERE a.name = 'main' RETURN b.name
```

## Gotchas
1. `search_graph(relationship="HTTP_CALLS")` filters nodes by degree — use `query_graph` with Cypher to see actual edges.
2. `query_graph` has a 200-row cap — use `search_graph` with degree filters for counting.
3. `trace_path` needs exact names — use `search_graph(name_pattern=...)` first.
4. `direction="outbound"` misses cross-service callers — use `direction="both"`.
5. Results are paged (`search_graph` default 50, max 500) — check `has_more` and use `offset`.
