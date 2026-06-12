---
name: kb-ingest
description: Ingest external integration docs (vendor specs, MIGs, API guides) into the kb knowledge base — conversion, figure descriptions, samples, eval wiring. Use when new spec documents need to become searchable.
user-invocable: true
---

$ARGUMENTS

You are ingesting **one external documentation set** (one vendor/spec facet)
into the kb knowledge base at `~/kb`. The procedure below is distilled from
the ingestions that worked (seb-camt, seb-pain001, seb-pain008,
pcr-cert-service) — follow it; each rule exists because skipping it bit us.

## Inputs

1. **Raw documents** under `~/kb/_private/<facet>/` (PDFs, spreadsheets,
   saved HTML, WSDL/XSD, sample files). `_private/` is gitignored and never
   indexed — it is the archive, `external/` holds the searchable versions.
2. **Facet name** — the directory `~/kb/external/<facet>/` and the derived
   `service:<facet>` tag. Lowercase kebab, vendor-scoped (`seb-camt`,
   `pcr-cert-service`). Ask if not given.
3. **Version on the wire** — when the set contains multiple spec versions,
   ask which version production actually speaks. Convert ONLY that one.
   Newer versions stay un-unpacked in `_private/` as forward reference.

## Hard rules

- **Never re-convert over hand-edited output.** Converted files carry
  manual figure descriptions; `convert.py` refuses to overwrite without
  `--force` — treat `--force` as "I accept losing hand edits".
- **Stem collisions**: a PDF and a spreadsheet of the same document share a
  stem — pass `--name` to give each its own output file.
- **Never claim a vendor sample shows what our services produce.** Phrase
  inline samples as "the message version/scheme <service> targets; whether
  our actual output matches is a gap-analysis question".
- **No pipe-masked failures**: don't chain `convert.py ... | grep ... && mv`
  — the guard's exit code gets swallowed by the pipe. Run steps separately.

## Procedure

### 1. Convert (from `~/kb`, with `uv run --extra convert`)

| Source | Command | Notes |
|---|---|---|
| born-digital PDF | `convert.py pdf F --service <facet> --images --no-ocr` | `--images` extracts figures into `<stem>_artifacts/` |
| scanned PDF | same without `--no-ocr` | |
| xlsx | `convert.py xlsx F --service <facet> [--name STEM]` | one `##` per worksheet |
| saved HTML | `convert.py html F --service <facet> [--name STEM]` | chrome cleanup follows |
| WSDL / XSD / XML | no converter — hand-write a note | prose intro (operations, key types, endpoints) + the file(s) verbatim in ```xml fences |

### 2. Figure exercise (PDFs with `--images`)

Raster figures contribute nothing searchable; describe every real one.

1. List the artifacts dir with dimensions
   (`sips -g pixelWidth -g pixelHeight`). **Page chrome** = repeated hashes
   and banner/logo dimensions (e.g. ~445×69, ≤100×70) → delete those
   `![Image](...)` lines from the markdown. Use exact filenames from `ls`,
   never extrapolate hashes.
2. View every remaining figure (Read tool) and insert a description
   directly after its image ref:
   - **Schema/XSD diagrams** — `Figure: <Element> (<Tag>, <Type>)
     structure:` followed by a fenced indented element tree with
     multiplicities `[1..1]`, `[0..1]`, `[0..inf]`. Cross-check against the
     XSD when available.
   - **Sequence/flow diagrams** — prose with the actual actor names,
     numbered steps and message names from the diagram.
   - **Screenshots / example messages** — prose stating the concrete
     field values shown (they are often the only place test parameters
     appear).
   - **Legends** — short prose; covers/logos stay bare or get removed.
3. Cleanup pass: make the document title a `#` heading (conversion often
   drops it), remove junk crops, restore section headings the converter
   mangled, fix captions that merged into body text.

### 3. HTML cleanup

Strip site chrome (nav trees, footers, "related links") — content usually
ends at the first related-links heading. Prepend a quoted source preface:
origin site/page, last-updated date, one line on what the page covers.

### 4. Samples

- Write a samples index note (`<facet>_samples_index.md`): what sample
  files exist in `_private/`, grouped by what they demonstrate.
- Inline the 1–3 highest-value samples verbatim (```xml fences) in their
  own notes with a prose intro — these answer "what does X actually look
  like" queries. Apply the no-overclaim rule above.

### 5. Wire up and verify

1. `~/kb/facets.toml`: add a one-line description for the new facet under
   `[tags]` (`"service:<facet>" = "..."`) — the server returns these in
   zero-hit tag listings and stamps them into the kb_find docstring.
2. `golden.toml`: add ≥1 case per major document. Write the query from
   memory as you would actually ask it — never by copying phrases out of
   the converted doc (that inflates keyword matching).
3. `kb sync`, then `kb eval` — all cases must hit.
4. Live check: `kb_find` with `tags=["service:<facet>"]` and a real
   question; confirm spec chunks come back with sensible text.
5. If the doc had very large tables, sanity-check chunk sizes (the
   chunker splits oversized tables and repeats headers — verify, don't
   assume).

### 6. Join to implementation (pointer only)

If payments-inventory flow notes integrate against this spec, the
`service:` frontmatter that joins them is owned by that repo's `flow-page`
skill — valid facet names are the `~/kb/external/` directory names. Don't
add frontmatter to inventory notes outside that workflow; just mention the
new facet is available.

## Report back

Files created under `external/<facet>/`, figure count described vs removed
as chrome, eval result, and one live query demonstrating retrieval.
