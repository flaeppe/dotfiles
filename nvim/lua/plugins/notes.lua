-- Reasoning notes: Petter's own reasoning about a piece of code, keyed to a
-- symbol rather than a line, written straight to `~/.plan` and shown back as
-- an indicator wherever that symbol is read again.
--
-- A note is a `## ` section in a
-- markdown file under `<root>/<repo>/reasoning/<relpath>.md`. Its truth is one
-- or more `ref:` lines of the form `repo@relpath[:Chain.Of.Symbols][+n]`; a
-- second reference (another file, another repo) rides in the same section via
-- `:NoteAdd`, and the section's home file is decided by sorting those `ref:`
-- tokens lexically and taking the first. Reachability never depends on where
-- the note is filed: everything below indexes and matches on `ref:` lines,
-- not on directory listings.
--
--   <Leader>nc (n/x)   capture a reference at the cursor (or over the visual
--                      selection) and open a compose buffer for the note body
--   :NoteAdd           add another reference to the open compose buffer
--   <Leader>nk (n)      hover the note for the marker under/above the cursor
--   <Leader>ne (n)      jump to the note's home file at its section
--   (passive)          a sign + light highlight at every resolvable `ref:`
--                      pointing into the current buffer
--
-- The drip backfill adds a second way into the same compose buffer, for
-- candidates parked by `reasoning-triage` in a queue of its own.
-- Three terminal-or-not decisions, not two: kept and dropped never resurface;
-- deferred does, but only once every undecided candidate is exhausted:
--
--   :NoteNext [args]   open the next candidate (`reasoning-queue next -n 1
--                      --json <args>`, args passed through verbatim; a bare
--                      non-flag argument is shorthand for `--feed <arg>`),
--                      prefilled with its ref(s), at:, source:, captured:
--                      and strength: (blank; `hunch` | `leaning` | `firm`,
--                      dropped on write if left blank), then its body
--   :wq                non-empty body: writes the note as usual, then
--                      `reasoning-queue decide <id> kept`. Empty body (a
--                      candidate-backed buffer only -- nothing after the
--                      header block but whitespace): writes nothing,
--                      `reasoning-queue decide <id> dropped`
--   :NoteSkip          `reasoning-queue decide <id> deferred`, discard the
--                      buffer, open the next candidate with the same args
--   :NoteDrop          `reasoning-queue decide <id> dropped`, discard the
--                      buffer without writing, open the next candidate with
--                      the same args
--
-- `nc`/`nk`/`ne` are unclaimed: nerdtree owns `<Leader>nn` and `<Leader>nf`
-- (nvim/lua/plugins/nerdtree.lua), nothing else starts with `<Leader>n`.

local M = {}

local NOTE_NAMESPACE = vim.api.nvim_create_namespace("note-markers")
-- Forward-declared: the passive-indicator section (below `M.write`) assigns
-- these; `M.write` calls them once a note lands, so both names must exist
-- before that call runs, not before it is read.
local rebuild_index, apply_indicators

-- Root and repo resolution -------------------------------------------------

--- Overridable so a headless test can point the whole surface at a temp
--- directory without touching `~/.plan`. Read fresh on every call: nothing
--- here may cache it, or an override set after this file loads would be
--- invisible to it.
local function notes_root()
    return vim.fn.expand(vim.g.reasoning_notes_root or "~/.plan")
end

--- Same override pattern as `notes_root`, for the `reasoning-queue` binary
--- `:NoteNext`/`:NoteSkip` shell out to.
local function queue_bin()
    return vim.fn.expand(vim.g.reasoning_queue_bin or "~/.plan/bin/reasoning-queue")
end

local function run(cmd, cwd)
    local result = vim.system(cmd, { cwd = cwd, text = true }):wait()
    return vim.trim(result.stdout or ""), result.code
end

--- The git worktree holding a file, which is not always the editor's cwd.
local function worktree_root(cwd)
    local out, code = run({ "git", "rev-parse", "--show-toplevel" }, cwd)
    return code == 0 and out or nil
end

--- The main checkout, reached from any of its linked worktrees -- its name is
--- the repository's, so a review worktree and the primary checkout resolve to
--- the same repo for the same file.
local function main_root(cwd)
    local out, code = run({ "git", "rev-parse", "--path-format=absolute", "--git-common-dir" }, cwd)
    if code ~= 0 then
        return nil
    end
    return vim.fs.dirname(out)
end

local function short_head(cwd)
    local out, code = run({ "git", "rev-parse", "--short", "HEAD" }, cwd)
    return code == 0 and out or nil
end

--- `repo, relpath` for a file path, or nil when it is not inside a checkout.
local function repo_and_relpath(filepath)
    if filepath == "" then
        return nil
    end
    local dir = vim.fn.fnamemodify(filepath, ":h")
    local wt_root = worktree_root(dir)
    local root = main_root(dir)
    if not wt_root or not root then
        return nil
    end
    if not vim.startswith(filepath, wt_root .. "/") then
        return nil
    end
    return vim.fs.basename(root), filepath:sub(#wt_root + 2)
end

-- Symbol chain: aerial first, treesitter parent-walk fallback --------------

--- Node types that stand for a definition worth naming in a chain, per
--- filetype. Go methods are not lexically nested in their receiver type, so
--- `method_declaration` is resolved together with its receiver below rather
--- than by nesting.
local FALLBACK_NODE_TYPES = {
    python = { function_definition = true, class_definition = true },
    go = { function_declaration = true, method_declaration = true, type_spec = true },
    typescript = { function_declaration = true, method_definition = true, class_declaration = true },
    typescriptreact = { function_declaration = true, method_definition = true, class_declaration = true },
}

local function node_name(node, bufnr)
    local fields = node:field("name")
    local name_node = fields and fields[1]
    return name_node and vim.treesitter.get_node_text(name_node, bufnr) or nil
end

--- The receiver type of a Go method (`EnvConfig` in `func (r EnvConfig) X()`,
--- `Server` in `func (s *Server) Y()`), or nil for a plain function.
local function go_receiver_type(method_node, bufnr)
    local receiver = method_node:field("receiver")[1]
    local param = receiver and receiver:named_child(0)
    local type_node = param and param:field("type")[1]
    if not type_node then
        return nil
    end
    if type_node:type() == "pointer_type" then
        type_node = type_node:named_child(0)
    end
    return type_node and vim.treesitter.get_node_text(type_node, bufnr) or nil
end

--- Outer-to-inner chain of enclosing definitions at a cursor position, via
--- treesitter alone: walk from the node under the cursor up to the root,
--- collecting names of nodes whose type is in this filetype's target set.
local function treesitter_chain(bufnr, row, col)
    local filetype = vim.bo[bufnr].filetype
    local allowed = FALLBACK_NODE_TYPES[filetype]
    if not allowed then
        return {}
    end
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
    if not ok or not parser then
        return {}
    end
    local root = parser:parse()[1]:root()
    local node = root:named_descendant_for_range(row, col, row, col)

    local inner_to_outer = {}
    while node do
        if allowed[node:type()] then
            local name = node_name(node, bufnr)
            if name then
                if node:type() == "method_declaration" then
                    table.insert(inner_to_outer, name)
                    local receiver = go_receiver_type(node, bufnr)
                    if receiver then
                        table.insert(inner_to_outer, receiver)
                    end
                else
                    table.insert(inner_to_outer, name)
                end
            end
        end
        node = node:parent()
    end

    local chain = {}
    for i = #inner_to_outer, 1, -1 do
        table.insert(chain, inner_to_outer[i])
    end
    return chain
end

--- Same chain, from aerial's already-computed symbol tree, when it has one
--- (`get_location` returns outer-to-inner; see aerial.nvim's `init.lua`).
--- Aerial needs an attached backend (LSP, or its own treesitter query pack)
--- to have populated symbols for this buffer, so an empty result here is
--- normal, not an error -- the caller falls back.
local function aerial_chain()
    local ok, aerial = pcall(require, "aerial")
    if not ok then
        return {}
    end
    local ok2, locations = pcall(aerial.get_location, true)
    if not ok2 or not locations then
        return {}
    end
    local chain = {}
    for _, location in ipairs(locations) do
        table.insert(chain, location.name)
    end
    return chain
end

--- The chain at a position, and which path produced it -- aerial commonly
--- has no symbols yet in a headless run, so callers should expect the
--- treesitter fallback there.
local function chain_at(bufnr, row, col)
    local chain = aerial_chain()
    if #chain > 0 then
        return chain, "aerial"
    end
    return treesitter_chain(bufnr, row, col), "treesitter"
end

-- Reference grammar: `repo@relpath[:Chain.Of.Symbols][+n]` -----------------

--- Parse one `ref:` token (without the `ref: ` prefix) into its parts. A
--- small hand-written parser, kept in three steps so each one stays
--- readable: repo, then relpath, then an optional `:symbol` and an optional
--- trailing `+n`.
local function parse_ref(token)
    local repo, rest = token:match("^([%w_%-%.]+)@(.+)$")
    if not repo then
        return nil
    end
    local path_part, symbol_part = rest:match("^([^:]+):(.+)$")
    local relpath = path_part or rest
    local symbol, span
    if symbol_part then
        local base, count = symbol_part:match("^(.+)%+(%d+)$")
        symbol = base or symbol_part
        span = count and tonumber(count) or nil
    else
        local base, count = relpath:match("^(.+)%+(%d+)$")
        if base then
            relpath, span = base, tonumber(count)
        end
    end
    return { repo = repo, relpath = relpath, symbol = symbol, span = span, token = token }
end

local function home_file_path(repo, relpath)
    return notes_root() .. "/" .. repo .. "/reasoning/" .. relpath .. ".md"
end

-- Compose buffer: one in flight, capture from anywhere -------------------

-- `nil`, or `{ bufnr = ... }` while a note is being written. A second
-- `<Leader>nc` refuses rather than opening a second draft; `:NoteAdd`
-- targets whichever one this holds.
local compose = nil

--- The literal `ref:` line a refs-empty candidate's compose buffer opens
--- with -- a candidate with no file anchor (a PR-conversation comment)
--- needs a reference chosen by hand before `:wq` will write it.
local PLACEHOLDER_REF = "ref: <fill in a reference>"

--- `+n` for a visual selection, cursor left at its top. Returns a count
--- instead of a preformatted `+n` string since the ref grammar formats it.
local function selected_span()
    if not vim.fn.mode():match("[vV]") then
        return 0
    end
    local first, last = vim.fn.line("v"), vim.fn.line(".")
    if first > last then
        first, last = last, first
    end
    vim.cmd("normal! \27")
    vim.api.nvim_win_set_cursor(0, { first, 0 })
    return last > first and (last - first + 1) or 0
end

--- The reference and provenance for the current buffer and cursor (or
--- selection). Returns nil and notifies on failure -- not in a git checkout,
--- or an unsaved buffer with no path.
local function capture_ref(span)
    local file = vim.fn.expand("%:p")
    local repo, relpath = repo_and_relpath(file)
    if not repo then
        vim.notify("Notes: not inside a git checkout", vim.log.levels.ERROR)
        return nil
    end
    local sha = short_head(vim.fn.fnamemodify(file, ":h"))
    if not sha then
        vim.notify("Notes: could not resolve HEAD", vim.log.levels.ERROR)
        return nil
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local chain = chain_at(bufnr, cursor[1] - 1, cursor[2])
    local symbol = #chain > 0 and table.concat(chain, ".") or nil

    local token = repo .. "@" .. relpath
    if symbol then
        token = token .. ":" .. symbol
    end
    if span and span > 0 then
        token = token .. "+" .. span
    end

    return {
        repo = repo,
        relpath = relpath,
        symbol = symbol,
        span = (span and span > 0) and span or nil,
        sha = sha,
        token = token,
    }
end

--- The heading token for one ref: its dotted chain (or the file's basename
--- for a whole-file ref), with `+n` appended only when `include_span` is set
--- -- the section heading carries the span of its first ref alone.
local function heading_part(ref, include_span)
    local part = ref.symbol or vim.fs.basename(ref.relpath)
    if include_span and ref.span then
        part = part .. " +" .. ref.span
    end
    return part
end

--- Find the `at:` line in a compose buffer (there is exactly one).
local function find_line(bufnr, prefix)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for i, line in ipairs(lines) do
        if vim.startswith(line, prefix) then
            return i, line
        end
    end
    return nil, nil
end

--- Add `repo@sha` to an `at:` line's comma-separated list, unless that repo
--- is already on it.
local function at_line_with(existing, repo, sha)
    local entry = repo .. "@" .. sha
    for token in existing:gmatch("[^,%s]+") do
        if token == entry then
            return existing
        end
    end
    return existing .. ", " .. entry
end

--- New compose buffer, cursor in insert mode on the blank body line. Uses
--- acwrite + `bufhidden = "hide"` so an abandoned `:q!` keeps the draft,
--- only `BufWipeout` releases the lock.
function M.capture()
    if compose and vim.api.nvim_buf_is_valid(compose.bufnr) and vim.api.nvim_buf_is_loaded(compose.bufnr) then
        vim.notify("Notes: a compose buffer is already open -- :wq or :bd! it first", vim.log.levels.ERROR)
        return
    end

    local span = selected_span()
    local ref = capture_ref(span)
    if not ref then
        return
    end

    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, ("reasoning-note://compose/%d"):format(bufnr))
    vim.bo[bufnr].buftype = "acwrite"
    vim.bo[bufnr].filetype = "markdown"
    vim.bo[bufnr].bufhidden = "hide"

    local lines = {
        "## " .. heading_part(ref, true),
        "ref: " .. ref.token,
        "at: " .. ref.repo .. "@" .. ref.sha,
        "captured: " .. os.date("%Y-%m-%d"),
        "strength: ",
        "",
    }
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modified = false

    vim.api.nvim_create_autocmd("BufWriteCmd", {
        buffer = bufnr,
        callback = function()
            M.write(bufnr)
        end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = bufnr,
        callback = function()
            if compose and compose.bufnr == bufnr then
                compose = nil
            end
        end,
    })

    compose = { bufnr = bufnr }

    vim.cmd("botright split")
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_win_set_cursor(0, { #lines, 0 })
    vim.cmd.startinsert({ bang = true })
end

--- Append a second (or third...) reference to the open compose buffer: one
--- more `ref:` line, and the repo added to `at:` if it is not there yet.
function M.note_add()
    if not (compose and vim.api.nvim_buf_is_valid(compose.bufnr)) then
        vim.notify("Notes: no compose buffer open -- start one with <Leader>nc", vim.log.levels.ERROR)
        return
    end
    local span = selected_span()
    local ref = capture_ref(span)
    if not ref then
        return
    end

    local bufnr = compose.bufnr
    local last_ref_lnum = 0
    for i, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
        if vim.startswith(line, "ref: ") then
            last_ref_lnum = i
        end
    end
    vim.api.nvim_buf_set_lines(bufnr, last_ref_lnum, last_ref_lnum, false, { "ref: " .. ref.token })

    local at_lnum, at_line = find_line(bufnr, "at: ")
    if at_lnum then
        local updated = "at: " .. at_line_with(at_line:sub(#"at: " + 1), ref.repo, ref.sha)
        vim.api.nvim_buf_set_lines(bufnr, at_lnum - 1, at_lnum, false, { updated })
    end
end

vim.api.nvim_create_user_command("NoteAdd", function()
    M.note_add()
end, { desc = "Add another reference to the open reasoning-note compose buffer" })

-- Writing the note ----------------------------------------------------------

--- Every repo named by any `ref:` line in a home file's full text (existing
--- content plus the section about to be appended).
local function services_union(existing_text, refs)
    local repos = {}
    for _, ref in ipairs(refs) do
        repos[ref.repo] = true
    end
    for line in (existing_text or ""):gmatch("[^\n]+") do
        local token = line:match("^ref:%s*(.+)$")
        local parsed = token and parse_ref(token)
        if parsed then
            repos[parsed.repo] = true
        end
    end
    local list = {}
    for repo in pairs(repos) do
        table.insert(list, repo)
    end
    table.sort(list)
    return list
end

--- Rewrite (or insert) the `services:` line of a frontmatter block, keeping
--- every other line untouched. `body` is the file's text after the closing
--- `---`.
local function with_services(frontmatter_lines, services)
    local out = {}
    local replaced = false
    for _, line in ipairs(frontmatter_lines) do
        if line:match("^services:") then
            table.insert(out, "services: [" .. table.concat(services, ", ") .. "]")
            replaced = true
        else
            table.insert(out, line)
        end
    end
    if not replaced then
        table.insert(out, "services: [" .. table.concat(services, ", ") .. "]")
    end
    return out
end

--- Parse the compose buffer into its parts: the parsed `ref:` lines (capture
--- order), the literal `at:` line, the literal `source:` line (nil unless
--- the candidate had one), the literal `captured:` line, the literal
--- `strength:` line (nil if absent; blank-valued left to the caller to
--- drop), and the body -- everything after the first blank line.
local function parse_compose(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local refs, at_line, source_line, captured_line, strength_line = {}, nil, nil, nil, nil
    local blank_lnum = nil
    for i, line in ipairs(lines) do
        if line:match("^ref:%s*") then
            local parsed = parse_ref(vim.trim(line:sub(5)))
            if parsed then
                table.insert(refs, parsed)
            end
        elseif line:match("^at:%s*") then
            at_line = line
        elseif line:match("^source:%s*") then
            source_line = line
        elseif line:match("^captured:%s*") then
            captured_line = line
        elseif line:match("^strength:%s*") then
            strength_line = line
        elseif line == "" and not blank_lnum then
            blank_lnum = i
        end
    end
    local body = {}
    if blank_lnum then
        body = vim.list_slice(lines, blank_lnum + 1, #lines)
    end
    while #body > 0 and body[1] == "" do
        table.remove(body, 1)
    end
    while #body > 0 and body[#body] == "" do
        table.remove(body)
    end
    return refs, at_line, source_line, captured_line or ("captured: " .. os.date("%Y-%m-%d")), strength_line, body
end

--- Notify and raise, so a refusal inside the BufWriteCmd callback actually
--- fails the `:write` (nvim otherwise treats a callback that merely returns
--- as a successful write: it clears 'modified' and lets a chained `:wq`
--- proceed to close the window, even though nothing was written).
local function refuse_write(msg)
    vim.notify(msg, vim.log.levels.ERROR)
    error(msg, 0)
end

--- Whether a parsed body is empty or whitespace-only -- "nothing after the
--- header block but whitespace".
local function body_is_blank(body)
    for _, line in ipairs(body) do
        if vim.trim(line) ~= "" then
            return false
        end
    end
    return true
end

--- `reasoning-queue decide <id> <decision>`. On success, notifies
--- `<decision> · <stdout>` -- reasoning-queue's own daily-progress line
--- (decision count against target, weekday streak, remaining) -- so
--- progress toward today's target surfaces without a separate check; on
--- failure notifies the error instead (not raising) -- the caller decides
--- what happens to the buffer either way.
local function queue_decide(id, decision, note_path)
    local cmd = { queue_bin(), "decide", id, decision }
    if note_path then
        vim.list_extend(cmd, { "--note", note_path })
    end
    local result = vim.system(cmd, { text = true }):wait()
    if result.code ~= 0 then
        vim.notify("Notes: reasoning-queue decide failed: " .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
        return false
    end
    vim.notify(decision .. " · " .. vim.trim(result.stdout or ""), vim.log.levels.INFO)
    return true
end

--- The empty-body `:wq` path for a candidate-backed buffer: write nothing,
--- mark the candidate dropped, close the buffer. Mirrors the closing half of
--- `M.write`'s success path (modified=false, release the compose lock,
--- deferred buffer deletion) without any of the file-writing half, since
--- there is no file to write.
local function drop_candidate(bufnr, candidate_id)
    queue_decide(candidate_id, "dropped")
    vim.bo[bufnr].modified = false
    compose = nil
    vim.schedule(function()
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end)
    vim.notify("Notes: dropped " .. candidate_id, vim.log.levels.INFO)
end

--- Write the note: pick the home file by sorting `ref:` tokens lexically,
--- create it with frontmatter or append a section to it, rewrite its
--- `services:` union, then close the compose buffer. A candidate-backed
--- buffer (`:NoteNext`) additionally marks the candidate `kept` in
--- `reasoning-queue` once the file is written -- or, with an empty body,
--- takes the `drop_candidate` path instead and never gets this far. A plain
--- (`<Leader>nc`) buffer has no candidate to drop, so an empty body there is
--- just another refusal.
function M.write(bufnr)
    local refs, at_line, source_line, captured_line, strength_line, body = parse_compose(bufnr)
    local candidate_id = vim.b[bufnr].reasoning_candidate_id

    if body_is_blank(body) then
        if candidate_id then
            drop_candidate(bufnr, candidate_id)
            return
        end
        refuse_write("Notes: empty body -- write something before :wq")
    end

    for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
        if line == PLACEHOLDER_REF then
            refuse_write("Notes: fill in a ref: before writing -- this candidate has no file anchor")
        end
    end

    if #refs == 0 then
        refuse_write("Notes: no ref: lines to write")
    end

    local by_home = vim.deepcopy(refs)
    table.sort(by_home, function(a, b)
        return a.token < b.token
    end)
    local home = by_home[1]
    local path = home_file_path(home.repo, home.relpath)

    local heading_parts = {}
    for i, ref in ipairs(refs) do
        table.insert(heading_parts, heading_part(ref, i == 1))
    end

    local section = { "## " .. table.concat(heading_parts, " · ") }
    for _, ref in ipairs(refs) do
        table.insert(section, "ref: " .. ref.token)
    end
    table.insert(section, at_line or "at:")
    if source_line then
        table.insert(section, source_line)
    end
    table.insert(section, captured_line)
    if strength_line and vim.trim(strength_line:match("^strength:%s*(.*)$") or "") ~= "" then
        table.insert(section, strength_line)
    end
    table.insert(section, "")
    vim.list_extend(section, body)

    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")

    local out
    if vim.fn.filereadable(path) == 0 then
        local services = services_union(nil, refs)
        out = {
            "---",
            "tags: reasoning",
            "repo: " .. home.repo,
            "path: " .. home.relpath,
            "services: [" .. table.concat(services, ", ") .. "]",
            "---",
            "",
        }
        vim.list_extend(out, section)
    else
        local existing = vim.fn.readfile(path)
        local close_idx = nil
        for i = 2, #existing do
            if existing[i] == "---" then
                close_idx = i
                break
            end
        end
        if not close_idx or existing[1] ~= "---" then
            refuse_write("Notes: " .. path .. " has no frontmatter block")
        end
        local frontmatter = vim.list_slice(existing, 2, close_idx - 1)
        local rest = vim.list_slice(existing, close_idx + 1, #existing)
        while #rest > 0 and rest[#rest] == "" do
            table.remove(rest)
        end
        local services = services_union(table.concat(existing, "\n"), refs)
        out = { "---" }
        vim.list_extend(out, with_services(frontmatter, services))
        table.insert(out, "---")
        vim.list_extend(out, rest)
        table.insert(out, "")
        vim.list_extend(out, section)
    end

    vim.fn.writefile(out, path)
    vim.notify("Notes: wrote " .. path, vim.log.levels.INFO)

    vim.bo[bufnr].modified = false
    compose = nil
    vim.schedule(function()
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end)

    rebuild_index()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" then
            apply_indicators(buf)
        end
    end

    if candidate_id and queue_decide(candidate_id, "kept", path) then
        vim.notify("Notes: " .. candidate_id .. " marked kept", vim.log.levels.INFO)
    end
end

-- Candidate queue: :NoteNext / :NoteSkip ------------------------------------

--- Open a compose buffer prefilled from a `reasoning-queue next --json`
--- candidate: one `ref:` per entry in `candidate.refs` (or the placeholder
--- when it is empty), `at:`, `source:`, `captured:` = the candidate's own
--- date, `strength:` blank, then its body. The heading reuses `parse_ref` +
--- `heading_part` rather than the candidate's `title`,
--- which is only a fallback for the refs-empty case (there is no ref to
--- derive a heading from). Same acwrite/bufhidden pattern as `M.capture`.
--- `args` is the (normalized) argument string `reasoning-queue next` was
--- called with, remembered on the buffer so `:NoteSkip`/`:NoteDrop` fetch
--- the next candidate under the same filter.
local function open_candidate_buffer(candidate, args)
    local refs = {}
    for _, token in ipairs(candidate.refs or {}) do
        local parsed = parse_ref(token)
        if parsed then
            table.insert(refs, parsed)
        end
    end

    local heading
    if #refs > 0 then
        local parts = {}
        for i, ref in ipairs(refs) do
            table.insert(parts, heading_part(ref, i == 1))
        end
        heading = table.concat(parts, " · ")
    else
        heading = candidate.title or "untitled"
    end

    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, ("reasoning-note://compose/%d"):format(bufnr))
    vim.bo[bufnr].buftype = "acwrite"
    vim.bo[bufnr].filetype = "markdown"
    vim.bo[bufnr].bufhidden = "hide"

    local lines = { "## " .. heading }
    if #refs > 0 then
        for _, token in ipairs(candidate.refs) do
            table.insert(lines, "ref: " .. token)
        end
    else
        table.insert(lines, PLACEHOLDER_REF)
    end
    table.insert(lines, "at: " .. table.concat(candidate.at or {}, ", "))
    table.insert(lines, "source: " .. (candidate.source or ""))
    table.insert(lines, "captured: " .. (candidate.captured or os.date("%Y-%m-%d")))
    table.insert(lines, "strength: ")
    table.insert(lines, "")
    vim.list_extend(lines, vim.split(candidate.body or "", "\n", { plain = true }))

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modified = false

    vim.b[bufnr].reasoning_candidate_id = candidate.id
    vim.b[bufnr].reasoning_candidate_args = args

    vim.api.nvim_create_autocmd("BufWriteCmd", {
        buffer = bufnr,
        callback = function()
            M.write(bufnr)
        end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = bufnr,
        callback = function()
            if compose and compose.bufnr == bufnr then
                compose = nil
            end
        end,
    })

    compose = { bufnr = bufnr }

    vim.cmd("botright split")
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_win_set_cursor(0, { #lines, 0 })
end

--- A bare single token with no leading dash is the legacy `:NoteNext <feed>`
--- shorthand, rewritten to `--feed <feed>`; anything else -- already flagged
--- (`--repo api --min-score 2`), or empty -- passes through unchanged for
--- `reasoning-queue` to interpret (or reject). This file does not track
--- which flags the script supports; a rejected flag surfaces as a failed
--- command below, same as any other `reasoning-queue` error.
local function normalize_next_args(args)
    if not args then
        return nil
    end
    local trimmed = vim.trim(args)
    if trimmed == "" then
        return nil
    end
    if not trimmed:find("%s") and not vim.startswith(trimmed, "-") then
        return "--feed " .. trimmed
    end
    return trimmed
end

--- `reasoning-queue next -n 1 --json <args>`, opened as a candidate compose
--- buffer. Refuses like `M.capture` when one is already open; reports the
--- queue drained (`nothing left`) rather than opening anything.
function M.note_next(args)
    if compose and vim.api.nvim_buf_is_valid(compose.bufnr) and vim.api.nvim_buf_is_loaded(compose.bufnr) then
        vim.notify("Notes: a compose buffer is already open -- :wq or :bd! it first", vim.log.levels.ERROR)
        return
    end

    local normalized = normalize_next_args(args)
    local cmd = { queue_bin(), "next", "-n", "1", "--json" }
    if normalized then
        vim.list_extend(cmd, vim.split(normalized, "%s+", { trimempty = true }))
    end
    local result = vim.system(cmd, { text = true }):wait()
    if result.code ~= 0 then
        vim.notify("Notes: reasoning-queue next failed: " .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
        return
    end

    local out = vim.trim(result.stdout or "")
    if out == "" or out == "nothing left" then
        vim.notify("Notes: queue is drained" .. (normalized and (" for " .. normalized) or ""), vim.log.levels.INFO)
        return
    end

    local ok, candidate = pcall(vim.json.decode, vim.split(out, "\n", { plain = true })[1])
    if not ok or type(candidate) ~= "table" then
        vim.notify("Notes: could not parse reasoning-queue output", vim.log.levels.ERROR)
        return
    end

    open_candidate_buffer(candidate, normalized)
end

--- Mark the open candidate deferred ("not now" -- resurfaces once every
--- undecided candidate is exhausted) and discard the compose buffer without
--- writing, then open the next candidate with the same args. Bound to
--- `:NoteSkip` -- despite the name, this defers rather than drops outright.
function M.note_defer()
    if not (compose and vim.api.nvim_buf_is_valid(compose.bufnr)) then
        vim.notify("Notes: no compose buffer open", vim.log.levels.ERROR)
        return
    end
    local bufnr = compose.bufnr
    local candidate_id = vim.b[bufnr].reasoning_candidate_id
    if not candidate_id then
        vim.notify("Notes: this compose buffer has no candidate to defer", vim.log.levels.ERROR)
        return
    end
    local args = vim.b[bufnr].reasoning_candidate_args

    if not queue_decide(candidate_id, "deferred") then
        return
    end

    compose = nil
    vim.bo[bufnr].modified = false
    vim.api.nvim_buf_delete(bufnr, { force = true })

    M.note_next(args)
end

--- Mark the open candidate dropped (won't resurface) and discard the compose
--- buffer without writing, then open the next candidate with the same args
--- -- the one-keystroke path for the low-score tail. Outside a
--- candidate-backed compose buffer, notifies and does nothing.
function M.note_drop()
    if not (compose and vim.api.nvim_buf_is_valid(compose.bufnr)) then
        vim.notify("Notes: no compose buffer open", vim.log.levels.ERROR)
        return
    end
    local bufnr = compose.bufnr
    local candidate_id = vim.b[bufnr].reasoning_candidate_id
    if not candidate_id then
        vim.notify("Notes: this compose buffer has no candidate to drop", vim.log.levels.ERROR)
        return
    end
    local args = vim.b[bufnr].reasoning_candidate_args

    drop_candidate(bufnr, candidate_id)
    M.note_next(args)
end

vim.api.nvim_create_user_command("NoteNext", function(cmd_opts)
    M.note_next(cmd_opts.args ~= "" and cmd_opts.args or nil)
end, { nargs = "*", desc = "Notes: open the next undecided (or deferred) reasoning-queue candidate, args passed to reasoning-queue next" })

vim.api.nvim_create_user_command("NoteSkip", function()
    M.note_defer()
end, { desc = "Notes: defer the open candidate and load the next" })

vim.api.nvim_create_user_command("NoteDrop", function()
    M.note_drop()
end, { desc = "Notes: drop the open candidate and load the next" })

-- Passive indicator: signs at every resolvable `ref:` -----------------------

-- Keyed `repo@relpath` -> list of `{ chain, span, token, home_file }`, built
-- from every `ref:` line under `<root>/*/reasoning/**/*.md` -- not from where
-- a note happens to be filed, so a note homed under another repo still
-- surfaces here.
local INDEX = {}
local index_built = false
-- Extmark id (namespaced by buffer) -> its index entry. Extmark opts only
-- accept a fixed set of recognised keys, so arbitrary payload data cannot
-- ride on the extmark itself; this is the side table that carries it.
local EXTMARK_DATA = {}

rebuild_index = function()
    INDEX = {}
    local root = notes_root()
    for _, path in ipairs(vim.fn.globpath(root, "*/reasoning/**/*.md", false, true)) do
        local ok, lines = pcall(vim.fn.readfile, path)
        if ok then
            for _, line in ipairs(lines) do
                local token = line:match("^ref:%s*(.+)$")
                local ref = token and parse_ref(token)
                if ref then
                    local key = ref.repo .. "@" .. ref.relpath
                    INDEX[key] = INDEX[key] or {}
                    table.insert(INDEX[key], {
                        chain = ref.symbol and vim.split(ref.symbol, ".", { plain = true }) or {},
                        span = ref.span,
                        token = ref.token,
                        home_file = path,
                    })
                end
            end
        end
    end
    index_built = true
end

local function ensure_index()
    if not index_built then
        rebuild_index()
    end
end

--- Descend a buffer's parse tree along a chain of names, narrowing the
--- search subtree at each step, to find the definition node a note's `ref:`
--- points at. A miss (returns nil) is not an error -- it is the drift signal:
--- the symbol moved, was renamed, or the buffer is on a branch where it no
--- longer exists.
local function descend_chain(bufnr, root_node, allowed, chain)
    local node = root_node
    local idx = 1
    while idx <= #chain do
        local wanted = chain[idx]
        local found, consumed = nil, 1

        local function search(scope)
            for child in scope:iter_children() do
                if child:named() then
                    local node_type = child:type()
                    if allowed[node_type] then
                        local name = node_name(child, bufnr)
                        if node_type == "method_declaration" then
                            local receiver = go_receiver_type(child, bufnr)
                            if receiver == wanted and chain[idx + 1] == name then
                                return child, 2
                            end
                        elseif node_type == "type_spec" then
                            -- A Go type is never the method's syntactic parent (the
                            -- receiver+method_declaration branch above is), so only
                            -- accept it as the chain's last element -- a note on the
                            -- type itself, not on something the chain still expects
                            -- to find nested inside it.
                            if name == wanted and idx == #chain then
                                return child, 1
                            end
                        elseif name == wanted then
                            return child, 1
                        end
                    end
                    local inner, inner_consumed = search(child)
                    if inner then
                        return inner, inner_consumed
                    end
                end
            end
            return nil
        end

        found, consumed = search(node)
        if not found then
            return nil
        end
        node = found
        idx = idx + consumed
    end
    return node
end

--- Place this buffer's markers: one per index entry for its `repo@relpath`,
--- resolved by descending the treesitter tree along the entry's chain.
apply_indicators = function(bufnr)
    vim.api.nvim_buf_clear_namespace(bufnr, NOTE_NAMESPACE, 0, -1)
    for key in pairs(EXTMARK_DATA) do
        if vim.startswith(key, bufnr .. ":") then
            EXTMARK_DATA[key] = nil
        end
    end

    local file = vim.api.nvim_buf_get_name(bufnr)
    local repo, relpath = repo_and_relpath(file)
    if not repo then
        return
    end
    local entries = INDEX[repo .. "@" .. relpath]
    if not entries then
        return
    end

    local filetype = vim.bo[bufnr].filetype
    local allowed = FALLBACK_NODE_TYPES[filetype]
    local root
    if allowed then
        local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
        root = ok and parser and parser:parse()[1]:root() or nil
    end

    for _, entry in ipairs(entries) do
        local lnum
        if #entry.chain == 0 then
            lnum = 1
        elseif root then
            local node = descend_chain(bufnr, root, allowed, entry.chain)
            lnum = node and (select(1, node:start()) + 1) or nil
        end
        if lnum then
            local end_lnum = entry.span and (lnum + entry.span - 1) or lnum
            local id = vim.api.nvim_buf_set_extmark(bufnr, NOTE_NAMESPACE, lnum - 1, 0, {
                sign_text = "»",
                sign_hl_group = "NoteMarkerSign",
                end_row = math.min(end_lnum, vim.api.nvim_buf_line_count(bufnr)) - 1,
                hl_group = "NoteMarkerSpan",
                hl_eol = false,
            })
            EXTMARK_DATA[bufnr .. ":" .. id] = entry
        end
    end
end

vim.api.nvim_set_hl(0, "NoteMarkerSign", { link = "DiagnosticHint", default = true })
vim.api.nvim_set_hl(0, "NoteMarkerSpan", { link = "Comment", default = true })

vim.api.nvim_create_autocmd({ "BufRead", "BufWinEnter" }, {
    callback = function(event)
        if vim.bo[event.buf].buftype ~= "" then
            return
        end
        ensure_index()
        apply_indicators(event.buf)
    end,
})

--- The entry behind the marker under, or nearest above, the cursor.
local function marker_at_cursor(bufnr)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, NOTE_NAMESPACE, 0, -1, {})
    if #marks == 0 then
        return nil
    end
    local cursor_lnum = vim.api.nvim_win_get_cursor(0)[1]
    local best
    for _, mark in ipairs(marks) do
        local lnum = mark[2] + 1
        if lnum <= cursor_lnum then
            best = mark
        end
    end
    best = best or marks[1]
    return EXTMARK_DATA[bufnr .. ":" .. best[1]]
end

--- The text of the section a `ref:` token belongs to, read fresh from its
--- home file: from the nearest preceding `## ` heading up to (not including)
--- the next one, or end of file.
local function section_text(home_file, token)
    local ok, lines = pcall(vim.fn.readfile, home_file)
    if not ok then
        return nil, nil
    end
    local ref_lnum
    for i, line in ipairs(lines) do
        if line == "ref: " .. token then
            ref_lnum = i
            break
        end
    end
    if not ref_lnum then
        return nil, nil
    end
    local start_lnum = ref_lnum
    while start_lnum > 1 and not vim.startswith(lines[start_lnum], "## ") do
        start_lnum = start_lnum - 1
    end
    local end_lnum = #lines
    for i = start_lnum + 1, #lines do
        if vim.startswith(lines[i], "## ") then
            end_lnum = i - 1
            break
        end
    end
    return vim.list_slice(lines, start_lnum, end_lnum), start_lnum
end

--- Hover the note text for the marker under/nearest the cursor. Not bound to
--- `K`: nvim 0.11 binds `K` to LSP hover and nothing here overrides it.
function M.hover()
    local entry = marker_at_cursor(vim.api.nvim_get_current_buf())
    if not entry then
        vim.notify("Notes: no note marker in this buffer", vim.log.levels.WARN)
        return
    end
    local text = section_text(entry.home_file, entry.token)
    if not text then
        vim.notify("Notes: could not read " .. entry.home_file, vim.log.levels.ERROR)
        return
    end
    vim.lsp.util.open_floating_preview(text, "markdown", { border = "rounded" })
end

function M.edit()
    local entry = marker_at_cursor(vim.api.nvim_get_current_buf())
    if not entry then
        vim.notify("Notes: no note marker in this buffer", vim.log.levels.WARN)
        return
    end
    local _, start_lnum = section_text(entry.home_file, entry.token)
    vim.cmd.edit(vim.fn.fnameescape(entry.home_file))
    if start_lnum then
        vim.api.nvim_win_set_cursor(0, { start_lnum, 0 })
        vim.cmd("normal! zz")
    end
end

-- Bindings ------------------------------------------------------------------

vim.keymap.set({ "n", "x" }, "<Leader>nc", M.capture, { desc = "Notes: capture a reference" })
vim.keymap.set("n", "<Leader>nk", M.hover, { desc = "Notes: hover the marker's note" })
vim.keymap.set("n", "<Leader>ne", M.edit, { desc = "Notes: edit the marker's home file" })

-- Published as a global, not returned: this file is inlined into init.lua by
-- nvim.nix rather than required as a module, and a `return` would end the whole
-- chunk -- everything nvim.nix concatenates after it becomes a syntax error.
_G.ReasoningNotes = M
