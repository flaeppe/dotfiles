-- Local PR review: markers, review scope, and the editor surfaces over both.
-- See docs/pr-review.md for the design this implements.
--
-- The marker grammar, which every function here parses or emits:
--
--   REVIEW[3]: this belongs in the domain layer      a finding
--   REVIEW[3]fix: extract to domain layer            apply as code, no prose
--   REVIEW[3]ask: why is the retry unbounded?        a question for the author
--   REVIEW[3]note: check the sibling flow            private; never reported
--   REVIEW[3]                                        another site for finding 3
--
-- One id, many sites: the site carrying a body is the primary, bare ones add
-- locations. Markers live in the code they annotate, so they move with it.

local fzf = require("fzf-lua")

local M = {}

local NAMESPACE = vim.api.nvim_create_namespace("review-markers")
-- Two patterns over one syntax: `FIND` locates a marker anywhere in a line,
-- `BODY` decides whether it carries text. Bare back-references have no colon.
local FIND = "REVIEW%[(%d+)%](%a*)"
local BODY = "^:%s*(.*)"
local KINDS = { fix = "ReviewMarkerFix", ask = "ReviewMarkerAsk", note = "ReviewMarkerNote" }

--- Parse every marker in one line of text. Returns a list, since nothing stops a
--- line from carrying two.
local function parse(line)
    local found = {}
    local offset = 1
    while true do
        local start, stop, id, kind = line:find(FIND, offset)
        if not start then
            return found
        end
        local text = line:sub(stop + 1):match(BODY)
        table.insert(found, {
            id = tonumber(id),
            kind = kind ~= "" and kind or nil,
            text = text,
            col = start,
            stop = stop,
        })
        offset = stop + 1
    end
end

local function highlight_group(marker)
    return marker.kind and KINDS[marker.kind] or "ReviewMarker"
end

--- Markers in a buffer, in line order.
function M.buffer_markers(bufnr)
    bufnr = bufnr or 0
    local markers = {}
    for lnum, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
        for _, marker in ipairs(parse(line)) do
            marker.lnum = lnum
            marker.line_length = #line
            table.insert(markers, marker)
        end
    end
    return markers
end

--- Every marker under `root`, defaulting to this worktree.
---
--- Ordered by id, then the site carrying the body ahead of its back-references, then
--- file and line -- so a group reads as a group wherever it is rendered, and callers
--- may treat the first site of an id as its primary.
function M.project_markers(root)
    root = root or M.root()
    local result = vim.system({ "rg", "--vimgrep", "--no-heading", "REVIEW\\[\\d+\\]", root }, { text = true }):wait()
    local markers = {}
    for _, hit in ipairs(vim.split(result.stdout or "", "\n", { trimempty = true })) do
        local file, lnum, _, line = hit:match("^(.-):(%d+):(%d+):(.*)$")
        if file then
            for _, marker in ipairs(parse(line)) do
                marker.file = file
                marker.lnum = tonumber(lnum)
                table.insert(markers, marker)
            end
        end
    end
    table.sort(markers, function(a, b)
        if a.id ~= b.id then
            return a.id < b.id
        end
        if (a.text ~= nil) ~= (b.text ~= nil) then
            return a.text ~= nil
        end
        if a.file ~= b.file then
            return a.file < b.file
        end
        return a.lnum < b.lnum
    end)
    return markers
end

local function relative(path, root)
    return (path:gsub("^" .. vim.pesc(root .. "/"), ""))
end

--- Markers grouped into findings, one group per id, each with its primary site's body
--- and kind plus the locations of its back-references.
local function grouped(root)
    local groups, order = {}, {}
    for _, marker in ipairs(M.project_markers(root)) do
        local group = groups[marker.id]
        if not group then
            group = { id = marker.id, sites = {} }
            groups[marker.id] = group
            table.insert(order, group)
        end
        -- First bodied site wins, which is well defined only because the scan orders
        -- bodied sites ahead of back-references within an id.
        if marker.text and not group.text then
            group.text = marker.text
            group.kind = marker.kind
            group.file = marker.file
            group.lnum = marker.lnum
        else
            table.insert(group.sites, { file = marker.file, lnum = marker.lnum })
        end
    end
    return order
end

--- The review session directory. Walks up from the buffer so it resolves before
--- the directory exists, which is when `order` and `report` need it.
function M.root()
    local start = vim.fn.expand("%:p:h")
    if start == "" then
        start = vim.uv.cwd()
    end
    local found = vim.fs.find(".review", { path = start, upward = true, type = "directory" })[1]
    if found then
        return vim.fs.dirname(found)
    end
    local git = vim.fs.find(".git", { path = start, upward = true })[1]
    return git and vim.fs.dirname(git) or vim.uv.cwd()
end

local function review_dir()
    return M.root() .. "/.review"
end

--- Where markers are read from: the review worktree during a session, this worktree
--- otherwise. Paths found here are translated before being opened, since both
--- worktrees hold the same relative paths.
---
--- A finding is looked *up* there and opened *here*, so that jumping to one from the
--- stack lands on the copy with the suggestion applied -- the one that can be edited
--- -- rather than stranding you in a tree that holds nothing but markers. Line numbers
--- are approximate across the two, each shifted by what it carries: right file, right
--- region.
local function marker_root()
    local session = M.session()
    return session and session.review_worktree or M.root()
end

-- Session -----------------------------------------------------------------

local function read_json(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local raw = file:read("*a")
    file:close()
    local ok, decoded = pcall(vim.json.decode, raw)
    return ok and decoded or nil
end

--- The review session this worktree belongs to, or nil outside one. Written when the
--- session is created, once per worktree; `role` is what differs between the copies.
---
--- Worktree paths are canonicalised on the way in, because they arrive unresolved
--- while buffer names are resolved, and a symlinked path prefix is normal on macOS.
--- Translating a path from one worktree to the other needs both sides in the same
--- form, or it silently yields a path that does not exist.
function M.session()
    local session = read_json(review_dir() .. "/session.json")
    if not session then
        return nil
    end
    for _, key in ipairs({ "review_worktree", "stack_worktree" }) do
        session[key] = vim.uv.fs_realpath(session[key]) or session[key]
    end
    return session
end

local function git(args, cwd)
    local result = vim.system(vim.list_extend({ "git" }, args), { cwd = cwd, text = true }):wait()
    return vim.trim(result.stdout or ""), result.code, vim.trim(result.stderr or "")
end

local function lines_of(output)
    return #vim.split(output, "\n", { trimempty = true })
end

--- File counts for the stack's uncommitted work, split the way the review acts on
--- it: staged is accepted into the next commit, unstaged is still in flight.
---
--- A file a suggestion *adds* is untracked, and `git diff` never mentions one, so
--- it counts as unstaged -- an added file is exactly as unaccepted as an edited
--- one, and must not be missing from the total.
local function uncommitted(session)
    local staged = git({ "diff", "--cached", "--name-only" }, session.stack_worktree)
    local unstaged = git({ "diff", "--name-only" }, session.stack_worktree)
    local untracked = git({ "ls-files", "--others", "--exclude-standard" }, session.stack_worktree)
    return lines_of(staged), lines_of(unstaged) + lines_of(untracked)
end

--- Open a file at a line. Trivial on its own, but it is also the channel the AI
--- and the other worktree's editor reach in over the socket, so it stays a
--- command rather than a keymap.
vim.api.nvim_create_user_command("ReviewOpen", function(opts)
    local target = opts.fargs[1]
    if not target then
        return
    end
    vim.cmd.edit(vim.fn.fnameescape(target))
    local lnum = tonumber(opts.fargs[2])
    if lnum then
        vim.api.nvim_win_set_cursor(0, { math.min(lnum, vim.api.nvim_buf_line_count(0)), 0 })
        vim.cmd("normal! zz")
    end
end, { nargs = "+", complete = "file", desc = "Open a file at a line (also the remote entry point)" })

--- Open the same file and line in the other worktree's editor.
---
--- Reading and changing happen in different worktrees, so this is the bridge: noticing
--- something in one does not mean navigating to it by hand in the other.
function M.demo()
    local session = M.session()
    if not session then
        vim.notify("Not in a review session", vim.log.levels.WARN)
        return
    end
    local from, to, socket
    if session.role == "review" then
        from, to, socket = session.review_worktree, session.stack_worktree, session.stack_socket
    else
        from, to, socket = session.stack_worktree, session.review_worktree, session.review_socket
    end
    local path = vim.api.nvim_buf_get_name(0)
    if path == "" then
        vim.notify("Open a file first — this opens the same line in the other worktree", vim.log.levels.WARN)
        return
    end
    path = vim.uv.fs_realpath(path) or path
    if not vim.startswith(path, from .. "/") then
        vim.notify(
            string.format("%s is outside this worktree, so it has no counterpart", vim.fs.basename(path)),
            vim.log.levels.WARN
        )
        return
    end
    if not vim.uv.fs_stat(socket) then
        vim.notify("No editor listening on " .. socket, vim.log.levels.ERROR)
        return
    end
    local target = to .. "/" .. relative(path, from)
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    -- --remote-send reports transport failures only, so ask for the resulting
    -- cursor line back: a silent no-op there (an editor without this config
    -- loaded, say) would otherwise read as success.
    local result = vim.system({
        "nvim",
        "--server",
        socket,
        "--remote-expr",
        string.format(
            'execute("ReviewOpen %s %d") . luaeval("vim.api.nvim_win_get_cursor(0)[1]")',
            vim.fn.fnameescape(target),
            lnum
        ),
    }, { text = true }):wait()
    local landed_at = tonumber(vim.trim(result.stdout or ""))
    if result.code ~= 0 or landed_at ~= lnum then
        vim.notify(
            "Remote open failed: " .. (vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr) or "no response"),
            vim.log.levels.ERROR
        )
        return
    end
    vim.notify(string.format("→ %s:%d", vim.fs.basename(target), lnum))
end

-- Accept ------------------------------------------------------------------

--- Findings already carried by the stack, keyed by id. Derived from commit
--- subjects rather than kept in a state file, so it cannot drift from the branch.
--- A hint, not an authority: the diff against the stack base is what the review
--- *is*, and a finding whose commit was later reverted or dropped still shows
--- here. When the two disagree, believe the diff.
local function landed(session)
    local log = git({ "log", "--format=%s", session.pr_head .. "..HEAD" }, session.stack_worktree)
    local ids = {}
    for _, subject in ipairs(vim.split(log, "\n", { trimempty = true })) do
        local id = subject:match("REVIEW%[(%d+)%]")
        if id then
            ids[tonumber(id)] = true
        end
    end
    return ids
end

--- The commit message prepared for a finding while it was implemented, as lines, or nil.
---
--- The first line is the subject's *remainder*: the caller owns the `REVIEW[n]:` prefix,
--- so a malformed file can cost a commit its body but never its place in the landed set.
--- The rest is the reasoning -- what was ruled out, what was actually checked -- which
--- has to travel in the message because a squash keeps one message and discards the rest.
local function prepared_message(root, id)
    local path = string.format("%s/.review/messages/%d.md", root, id)
    if vim.fn.filereadable(path) ~= 1 then
        return nil
    end
    local lines = vim.fn.readfile(path)
    while lines[1] and lines[1]:match("^%s*$") do
        table.remove(lines, 1)
    end
    return lines[1] and lines or nil
end

--- Commit the staged changes as one accepted suggestion. The commit is the
--- grouping: one finding, one commit, however many files it touches.
--- `take_all` (the command's bang) stages every change first, for the common case
--- of taking a suggestion whole. Without it, only what you staged is accepted,
--- which is how a subset of scattered edits gets through.
function M.accept(id, take_all)
    local session = M.session()
    if not session then
        vim.notify("Not in a review session", vim.log.levels.WARN)
        return
    end
    if session.role ~= "stack" then
        vim.notify("Accept from the stack worktree -- the review worktree never commits", vim.log.levels.ERROR)
        return
    end
    -- The documentation pass edits code the *stack* introduced, so no marker describes it
    -- and there is no id for it to carry -- but it is still the reviewer's to accept, and
    -- accepting it by hand would miss the hook skip below that a fresh worktree needs.
    local documenting = id == "docs"
    if documenting then
        id = nil
    else
        id = tonumber(id)
    end
    if not id and not documenting then
        -- No id given: nobody should have to remember one. One candidate is
        -- unambiguous, several get a picker.
        local done = landed(session)
        local open = {}
        for _, group in ipairs(grouped(session.review_worktree)) do
            if group.kind ~= "note" and group.kind ~= "ask" and not done[group.id] then
                table.insert(open, group)
            end
        end
        if #open == 0 then
            vim.notify("No finding left to accept", vim.log.levels.WARN)
            return
        end
        if #open == 1 then
            return M.accept(open[1].id, take_all)
        end
        local labels, by_label = {}, {}
        for _, group in ipairs(open) do
            local label = string.format("[%d] %s", group.id, group.text or "(no body)")
            table.insert(labels, label)
            by_label[label] = group.id
        end
        fzf.fzf_exec(labels, {
            prompt = "accept> ",
            winopts = { title = " which finding does this change address? ", height = 0.4, width = 0.8 },
            actions = {
                ["default"] = function(selected)
                    if selected and by_label[selected[1]] then
                        M.accept(by_label[selected[1]], take_all)
                    end
                end,
            },
        })
        return
    end
    if take_all then
        git({ "add", "-A" }, session.stack_worktree)
    end
    local staged = git({ "diff", "--cached", "--name-only" }, session.stack_worktree)
    if staged == "" then
        vim.notify(
            "Nothing staged — <Leader>hs accepts a hunk, or :ReviewAccept! takes the whole change",
            vim.log.levels.WARN
        )
        return
    end
    -- A subject with no `REVIEW[n]` in it is what keeps a documentation commit out of the
    -- landed set, so it is never mistaken for a finding by anything reading the log.
    local message = { "docs: comments and docstrings for the suggestion stack" }
    if not documenting then
        local text
        for _, group in ipairs(grouped(session.review_worktree)) do
            if group.id == id then
                text = group.text
            end
        end
        if not text then
            vim.notify(string.format("No finding [%d] in %s", id, session.review_worktree), vim.log.levels.ERROR)
            return
        end
        -- The marker states the problem; a prepared message states the change and the
        -- reasoning behind it, which is what an author needs in order to trust a
        -- suggestion. Falling back to the marker keeps accepting a finding nothing
        -- prepared -- one written by hand, or taken before its implementation ran.
        message = prepared_message(session.review_worktree, id) or { text }
        message[1] = string.format("REVIEW[%d]: %s", id, message[1])
    end
    -- --no-verify because commit hooks routinely depend on tooling generated at
    -- install time and excluded from version control, which a fresh worktree
    -- therefore lacks -- and because this is a local suggestion that the author's own
    -- CI will check for real. A blocked accept would strand the change.
    --
    -- --cleanup=whitespace pins what a body may contain, rather than inheriting it: a
    -- checkout configuring `commit.cleanup=strip` silently eats every line opening with
    -- `#`, and a body written as markdown loses its headings to that without a word.
    local message_file = vim.fn.tempname()
    vim.fn.writefile(message, message_file)
    local _, code, err =
        git({ "commit", "--no-verify", "--cleanup=whitespace", "-F", message_file }, session.stack_worktree)
    vim.fn.delete(message_file)
    if code ~= 0 then
        vim.notify("Commit failed: " .. err, vim.log.levels.ERROR)
        return
    end
    -- An accept changes what every progress surface reports, so it is announced
    -- rather than pushed: surfaces subscribe instead of being called from here.
    vim.api.nvim_exec_autocmds("User", { pattern = "ReviewAccepted" })
    local files = #vim.split(staged, "\n", { trimempty = true })
    vim.notify(
        documenting and string.format("documentation accepted — %d file(s)", files)
            or string.format("[%d] accepted — %d file(s)", id, files)
    )
end

--- Findings and their state, with the counts in the window title. Per-finding
--- attribution of *uncommitted* work is deliberately not attempted -- it cannot
--- be done honestly, and landed-vs-open is the distinction that matters.
function M.status()
    local session = M.session()
    if not session then
        vim.notify("Not in a review session", vim.log.levels.WARN)
        return
    end
    local done = landed(session)
    local staged_count, unstaged_count = uncommitted(session)
    local counts = { landed = 0, open = 0, prose = 0 }
    local entries = {}
    for _, group in ipairs(grouped(session.review_worktree)) do
        if group.kind ~= "note" then
            local state
            if group.kind == "ask" then
                state = "prose"
            elseif done[group.id] then
                state = "landed"
            else
                state = "open"
            end
            counts[state] = counts[state] + 1
            table.insert(
                entries,
                string.format(
                    "%s:%d:1:%-7s [%d] %s",
                    relative(group.file or "?", session.review_worktree),
                    group.lnum or 1,
                    state,
                    group.id,
                    group.text or "(no body)"
                )
            )
        end
    end
    if #entries == 0 then
        vim.notify("No findings yet — run /pr-session, or annotate with <Leader>rc", vim.log.levels.WARN)
        return
    end
    local in_flight = staged_count + unstaged_count
    fzf.fzf_exec(entries, {
        prompt = "status> ",
        cwd = M.root(),
        previewer = "builtin",
        winopts = {
            title = string.format(
                " review %s — %d landed / %d open / %d prose / %d in flight ",
                session.pr,
                counts.landed,
                counts.open,
                counts.prose,
                in_flight
            ),
        },
        actions = { ["default"] = fzf.actions.file_edit_or_qf },
    })
end

-- Scope -------------------------------------------------------------------
--
-- What "the change" means, resolved once and read by every surface that shows one
-- -- the sign column, the file panel, the quickfix work list. Choosing scope per
-- surface is how a review ends up with three keys that disagree.

--- On the stack, the suggestion accumulates: after two rounds a diff against the
--- PR head shows the finding already accepted alongside the one being read now, and
--- grows with every accept. `round` is therefore the default -- only the
--- uncommitted work, which is exactly what the last implement step produced.
local function stack_scope()
    return vim.g.review_stack_scope == "whole" and "whole" or "round"
end

--- The revision the scope measures against, with a name for a title.
---
--- Always a single revision, never an `a..b` range, because these line numbers
--- address the files on disk. A commit range compares two commits and knows nothing
--- of the working tree -- so in the review worktree, where every marker inserts an
--- uncommitted line, its hunk positions drift by however many markers sit above
--- them and land on unchanged code. On the stack the working tree is the whole point
--- anyway: it is where everything not yet accepted lives.
local function change_range(session)
    if session.role == "review" then
        return session.merge_base, "the PR"
    end
    if stack_scope() == "whole" then
        return session.pr_head, "the whole suggestion"
    end
    return "HEAD", "this round"
end

--- Signs answer the scope's question.
---
--- At the PR head that is always what this PR changed, so the base is the merge
--- base. On the stack, `round` leaves the base at gitsigns' default, the **index**
--- -- which is what makes staged and unstaged separately visible. Unstaged signs
--- are worktree-against-index, staged signs are index-against-HEAD, so the sign
--- column alone says what is accepted, what is in flight, and what is settled.
--- Naming an explicit revision collapses both into one diff and throws that away,
--- forcing a trip to the file panel to answer what the gutter could.
local function apply_scope(session)
    local ok, gitsigns = pcall(require, "gitsigns")
    if not ok then
        return
    end
    if session.role == "review" then
        gitsigns.change_base(session.merge_base, true)
        return
    end
    gitsigns.change_base(stack_scope() == "whole" and session.pr_head or nil, true)
end

--- With no revision the file panel splits into working-tree and staged sections,
--- which is the same distinction the sign column draws -- so `round` passes no
--- revision rather than the equivalent `HEAD`.
local function open_diff(session)
    -- The one place a commit range is right: the file panel renders its own buffers,
    -- so it can show the PR exactly as the author wrote it, without the marker lines
    -- the working tree carries. Nothing here points at a line on disk.
    if session.role == "review" then
        vim.cmd(string.format("DiffviewOpen %s..%s", session.merge_base, session.pr_head))
        return
    end
    if stack_scope() == "round" then
        vim.cmd("DiffviewOpen")
        return
    end
    vim.cmd("DiffviewOpen " .. change_range(session))
end

-- Statusline --------------------------------------------------------------
--
-- Which worktree this editor is rooted in, how much of the review has landed, and
-- what "the change" currently means. Permanently, not behind a key: those three
-- decide what every other key will do, and they are exactly what a few hours away
-- erases. The two worktrees also hold the same paths, so a filename alone never
-- says which tree you are standing in.
--
-- Coloured differently per role so it registers without being read.

vim.api.nvim_set_hl(0, "ReviewRoleReview", { link = "DiagnosticWarn", default = true })
vim.api.nvim_set_hl(0, "ReviewRoleStack", { link = "DiagnosticOk", default = true })

-- `base` is captured once: this prepends to the statusline, so re-rendering off a
-- previously rendered value would stack tags on every refresh.
local tag = { base = nil, progress = "" }

local function render_tag(session)
    tag.base = tag.base or vim.o.statusline
    local parts = { session.role:upper(), tag.progress }
    if session.role == "stack" then
        table.insert(parts, stack_scope())
    end
    vim.opt.statusline = string.format(
        "%%#%s# %s %%* ",
        session.role == "review" and "ReviewRoleReview" or "ReviewRoleStack",
        table.concat(parts, " · ")
    ) .. tag.base
end

--- Accepted against implementable -- the honest form of "how far in am I".
---
--- Deliberately not a round number: nothing records how many times the implement
--- step has run, so any such counter would be invented, and one that silently
--- stopped incrementing would be worse than none.
---
--- Recomputed on events rather than per redraw. A `git log` plus a ripgrep pass over
--- the worktree is ~100ms, which a statusline redraws far too often to afford.
local function refresh_tag(session)
    session = session or M.session()
    if not session then
        return
    end
    local done = landed(session)
    local total, accepted = 0, 0
    for _, group in ipairs(grouped(session.review_worktree)) do
        if group.kind ~= "note" and group.kind ~= "ask" then
            total = total + 1
            if done[group.id] then
                accepted = accepted + 1
            end
        end
    end
    tag.progress = total > 0 and string.format("%d/%d", accepted, total) or "no findings"
    render_tag(session)
end

-- The other worktree's editor and the AI both change this session's state, so
-- regaining focus is the moment the tag is most likely to be stale. Not on write:
-- a marker you just typed only changes the total, and paying 100ms per save for
-- that is the wrong trade.
vim.api.nvim_create_autocmd("FocusGained", {
    callback = function()
        refresh_tag()
    end,
})

vim.api.nvim_create_autocmd("User", {
    pattern = "ReviewAccepted",
    callback = function()
        refresh_tag()
    end,
})

--- Switch the stack between this round's uncommitted work and the whole
--- accumulated suggestion. Everything follows: the gutter, the statusline,
--- <Leader>rD, <Leader>rq.
function M.toggle_scope()
    local session = M.session()
    if not session then
        vim.notify("Not in a review session", vim.log.levels.WARN)
        return
    end
    if session.role ~= "stack" then
        vim.notify("The review worktree always shows the PR's own diff", vim.log.levels.WARN)
        return
    end
    vim.g.review_stack_scope = stack_scope() == "whole" and "round" or "whole"
    apply_scope(session)
    render_tag(session)
    local _, label = change_range(session)
    -- A diff already on screen is showing the old scope, so re-render it rather
    -- than leaving the toggle looking like it did nothing.
    if next(require("diffview.lib").views) then
        vim.cmd("DiffviewClose")
        open_diff(session)
    end
    vim.notify("Scope: " .. label)
end

-- Orientation -------------------------------------------------------------

--- The summary's opening prose, or nil.
---
--- Only the opening: the summary is written answer-first, so its first prose block is the
--- whole review in a few sentences and everything after it is support. That block is the
--- altitude this page holds; the rest is a document, and a document here would cost the
--- page the one property that makes it worth opening -- that it can be read at a glance.
---
--- The block ends where the prose does -- at the next blank line or heading -- so its length
--- is the summary's to decide. The cap is a backstop for prose that outgrew its own format,
--- and it announces itself rather than stopping mid-sentence, since a page that silently
--- truncates a paragraph reads as broken rather than as abridged.
local function summary_opening(dir)
    local path = dir .. "/summary.md"
    if vim.fn.filereadable(path) ~= 1 then
        return nil
    end
    local out, truncated = {}, false
    for _, line in ipairs(vim.fn.readfile(path)) do
        if line:match("^#") then
            if #out > 0 then
                break
            end
        elseif line ~= "" then
            if #out == 10 then
                truncated = true
                break
            end
            table.insert(out, line)
        elseif #out > 0 then
            break
        end
    end
    if #out == 0 then
        return nil
    end
    if truncated then
        table.insert(out, "…")
    end
    return out
end

--- Where the session stands, and the single next action.
---
--- The orientation surface, and the one opened at session start: a review worktree is
--- useless until you know which phase you are in, and every key that depends on an
--- artifact that may not exist yet points back here.
function M.panel()
    local session = M.session()
    if not session then
        vim.notify("Not in a review session — start one with `review <pr>`", vim.log.levels.WARN)
        return
    end
    local reviewing = session.role == "review"
    local markers = grouped(session.review_worktree)
    local has_order = vim.uv.fs_stat(session.review_worktree .. "/.review/order.json") ~= nil
    local has_findings = vim.uv.fs_stat(session.review_worktree .. "/.review/findings.md") ~= nil
    -- Always the review worktree's: one `.review/` per session, beside the markers,
    -- whichever worktree produced the artifact.
    local has_assembled = vim.uv.fs_stat(session.review_worktree .. "/.review/out/plan.sh") ~= nil
    local summary_path = session.review_worktree .. "/.review/summary.md"
    local opening = summary_opening(session.review_worktree .. "/.review")
    local done = landed(session)
    local staged_count, unstaged_count = uncommitted(session)
    local in_flight = staged_count + unstaged_count

    local open_count, ask_count, landed_count = 0, 0, 0
    for _, group in ipairs(markers) do
        if group.kind == "ask" then
            ask_count = ask_count + 1
        elseif group.kind ~= "note" then
            if done[group.id] then
                landed_count = landed_count + 1
            else
                open_count = open_count + 1
            end
        end
    end

    local next_step
    if reviewing then
        if #markers == 0 and not has_order then
            next_step = "run  /pr-session  in the shell pane — it writes the review order and drafts markers"
        elseif not has_findings then
            next_step =
                "<Leader>ro to walk the order · <Leader>rc/rf/ra to annotate · <Leader>rw when the set is right"
        elseif has_assembled then
            next_step = "assembled, not sent — read  .review/out/  then  /pr-session publish"
        elseif open_count > 0 then
            next_step = "findings harvested — run  /pr-session implement  in the stack tab"
        else
            next_step = "every finding resolved — run  /pr-session assemble  in the stack tab"
        end
    elseif in_flight > 0 then
        next_step = "read the change · <Leader>hs accepts hunks · :ReviewAccept <id> takes it into the review"
    elseif open_count > 0 then
        next_step = "run  /pr-session implement  in the shell pane"
    elseif has_assembled then
        -- `assemble` writes and stops; nothing has left the machine yet, and the whole
        -- point of the split is that this page is where you find that out.
        next_step = "assembled, not sent — read  .review/out/  then  /pr-session publish"
    elseif landed_count > 0 or ask_count > 0 then
        next_step = "nothing in flight — run  /pr-session assemble  to build the review"
    else
        next_step = "no findings yet — curate them in the review tab first"
    end

    local lines = {
        string.format("review %s — %s", session.pr, session.title or ""),
        session.url or "",
        "",
        reviewing and "role  review · annotate here; this worktree never commits"
            or "role  stack · suggestions land here; one commit per accepted finding",
        string.format("stack %s", session.stack_branch or "?"),
        "",
        string.format("  order      %s", has_order and "ready" or "not yet"),
        string.format("  summary    %s", opening and "written" or "not yet"),
        string.format("  findings   %s", has_findings and "harvested" or "not harvested"),
        string.format("  open       %d", open_count),
        string.format("  accepted   %d", landed_count),
        string.format("  questions  %d", ask_count),
        string.format("  staged     %d file(s) — ready for :ReviewAccept", staged_count),
        string.format("  unstaged   %d file(s) — not accepted yet", unstaged_count),
        string.format("  assembled  %s", has_assembled and ".review/out/ — local only, not sent" or "not yet"),
        "",
        "next  " .. next_step,
        "",
        "      <Leader>rD  browse the change · <Leader>rq  the same change as a work list",
        "      <Leader>rl  findings · <Leader>rt  their states · <Leader>rp  refresh this page",
        "      <Leader>rj  same spot in the other worktree · <Leader>?  every key",
        -- This page reports state; it cannot reason about it. When the two disagree, or
        -- when the next action is not the obvious one, that is what the session's own
        -- diagnosis is for -- so the escape hatch is named here rather than remembered.
        "      stuck?  /pr-session help <what you are unsure about>",
    }

    -- Ahead of the state table, because it is what those counts are counts of. Coming back
    -- after hours away, what has gone is why any of this mattered, not the numbers -- and
    -- reading it here costs no key and no phase transition, where reaching the document
    -- through a harvest would rewrite findings.md from a set still being curated.
    if opening then
        local prose = { "", "summary" }
        for _, line in ipairs(opening) do
            table.insert(prose, "  " .. line)
        end
        table.insert(prose, "  full: " .. summary_path .. "  (gf)")
        for i = #prose, 1, -1 do
            table.insert(lines, 6, prose[i])
        end
    end

    if not reviewing then
        local _, scope = change_range(session)
        table.insert(lines, string.format("      <Leader>rb  scope — currently %s", scope))
    end

    if session.pr_tip and session.pr_tip ~= session.pr_head then
        table.insert(lines, 4, "")
        table.insert(
            lines,
            5,
            string.format("!!    the PR has moved on upstream — this session reviews %s", session.pr_head:sub(1, 9))
        )
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"
    vim.api.nvim_set_current_buf(buf)
end

--- Listen on the session's socket so the AI and the other worktree's editor can
--- reach in. Deferred to VimEnter so a session opened via `-c` has settled.
vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        vim.schedule(function()
            local session = M.session()
            if not session then
                return
            end
            local socket = session.role == "review" and session.review_socket or session.stack_socket
            -- A killed editor leaves its socket file behind, so mere existence
            -- proves nothing. Probe it, and clear a dead one -- otherwise every
            -- restart after a crash silently declines to serve.
            if vim.uv.fs_stat(socket) then
                local ok, channel = pcall(vim.fn.sockconnect, "pipe", socket, { rpc = true })
                if ok and channel ~= 0 then
                    pcall(vim.fn.chanclose, channel)
                else
                    os.remove(socket)
                end
            end
            if not vim.uv.fs_stat(socket) then
                pcall(vim.fn.serverstart, socket)
            end
            apply_scope(session)
            refresh_tag(session)
        end)
    end,
})

-- Insert ------------------------------------------------------------------

--- Re-scanned on every insert rather than cached, because the AI can add markers
--- to the worktree while this session is open. Loaded buffers are scanned
--- alongside disk: markers you have typed but not written yet are still taken,
--- and ripgrep cannot see them.
local function next_id()
    local highest = 0
    for _, marker in ipairs(M.project_markers()) do
        highest = math.max(highest, marker.id)
    end
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            for _, marker in ipairs(M.buffer_markers(bufnr)) do
                highest = math.max(highest, marker.id)
            end
        end
    end
    return highest + 1
end

--- Wrap text in the buffer's comment syntax, falling back to `#` where the filetype
--- declares none.
local function commented(text)
    local template = vim.bo.commentstring
    if template == "" then
        template = "# %s"
    end
    -- A function replacement, so a `%` in the text is not read as a capture reference.
    return (template:gsub("%%s", function()
        return text
    end))
end

local function insert_line(text)
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local indent = vim.api.nvim_get_current_line():match("^%s*")
    local line = indent .. commented(text)
    vim.api.nvim_buf_set_lines(0, lnum - 1, lnum - 1, false, { line })
    vim.api.nvim_win_set_cursor(0, { lnum, #line })
end

--- A new marker above the cursor, cursor left in insert mode at the end of it.
function M.insert(kind)
    insert_line(string.format("REVIEW[%d]%s: ", next_id(), kind or ""))
    vim.cmd.startinsert({ bang = true })
end

--- A bare back-reference to a finding that already exists elsewhere.
function M.link()
    local groups = grouped()
    if #groups == 0 then
        vim.notify("No finding to link to yet — write one with <Leader>rc first", vim.log.levels.WARN)
        return
    end
    local labels, by_label = {}, {}
    for _, group in ipairs(groups) do
        local label = string.format("[%d]%s %s", group.id, group.kind and (" " .. group.kind) or "", group.text or "")
        table.insert(labels, label)
        by_label[label] = group.id
    end
    fzf.fzf_exec(labels, {
        prompt = "link> ",
        winopts = { title = " link this location to a finding ", height = 0.5, width = 0.8 },
        actions = {
            ["default"] = function(selected)
                local id = selected and by_label[selected[1]]
                if id then
                    insert_line(string.format("REVIEW[%d]", id))
                end
            end,
        },
    })
end

--- Delete the marker on the cursor line, or the one directly above it -- markers
--- sit above the code they annotate, so the cursor is usually on that code.
function M.delete()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    for _, candidate in ipairs({ lnum, lnum - 1 }) do
        if candidate >= 1 then
            local line = vim.api.nvim_buf_get_lines(0, candidate - 1, candidate, false)[1]
            if line and #parse(line) > 0 then
                vim.api.nvim_buf_set_lines(0, candidate - 1, candidate, false, {})
                return
            end
        end
    end
    vim.notify("No marker on this line or the one above it", vim.log.levels.WARN)
end

-- Navigate ----------------------------------------------------------------

function M.jump(direction)
    local markers = M.buffer_markers(0)
    if #markers == 0 then
        vim.notify("No markers in this file — <Leader>rl lists them across the worktree", vim.log.levels.WARN)
        return
    end
    local current = vim.api.nvim_win_get_cursor(0)[1]
    local target
    if direction > 0 then
        for _, marker in ipairs(markers) do
            if marker.lnum > current then
                target = marker
                break
            end
        end
        target = target or markers[1]
    else
        for index = #markers, 1, -1 do
            if markers[index].lnum < current then
                target = markers[index]
                break
            end
        end
        target = target or markers[#markers]
    end
    vim.api.nvim_win_set_cursor(0, { target.lnum, target.col - 1 })
end

-- Lists -------------------------------------------------------------------

--- The change in a file panel, at whatever the current scope is.
function M.diff()
    local session = M.session()
    if not session then
        vim.notify("Not in a review session", vim.log.levels.WARN)
        return
    end
    -- Toggling: the same key that opened it closes it, so there is always a way
    -- out without knowing diffview's own bindings.
    if next(require("diffview.lib").views) then
        vim.cmd("DiffviewClose")
        return
    end
    open_diff(session)
end

--- The same change as a work list: one quickfix entry per hunk, in the files you can
--- edit. The quickfix list rather than a bespoke surface, so walking it costs no new
--- motions -- two renderings of one scope.
function M.hunks()
    local session = M.session()
    if not session then
        vim.notify("Not in a review session", vim.log.levels.WARN)
        return
    end
    local range, label = change_range(session)
    local root = M.root()
    -- -I drops any hunk whose changed lines are *all* markers, so annotating a file
    -- does not add work to the list. A marker sitting among real changes keeps its
    -- hunk, which is right -- that hunk still has to be visited.
    local out = git({ "diff", "-U0", "-I", "REVIEW\\[[0-9]+\\]", range }, root)
    local items, file = {}, nil
    for _, line in ipairs(vim.split(out, "\n", { trimempty = true })) do
        local target = line:match("^%+%+%+ b/(.*)$")
        if target then
            file = target
        elseif file then
            -- @@ -old,n +new,m @@ trailing-context. The `,m` is omitted when the
            -- hunk is one line, so the count has to be consumed as opaque
            -- non-space -- matching only the omitted form drops every multi-line
            -- hunk without saying so.
            local lnum, context = line:match("^@@ %-%S+ %+(%d+)%S* @@%s*(.*)$")
            if lnum then
                table.insert(items, {
                    filename = root .. "/" .. file,
                    lnum = math.max(1, tonumber(lnum)),
                    text = context ~= "" and context or "changed",
                })
            end
        end
    end
    -- A file the suggestion adds has no hunks to parse, so it needs an entry of its
    -- own or it is missing from the work list entirely. First, because a new file is
    -- the largest thing in a change and the least expected.
    if session.role == "stack" then
        local untracked = git({ "ls-files", "--others", "--exclude-standard" }, root)
        for _, path in ipairs(vim.split(untracked, "\n", { trimempty = true })) do
            table.insert(items, 1, { filename = root .. "/" .. path, lnum = 1, text = "new file" })
        end
    end
    if #items == 0 then
        vim.notify("Nothing in " .. label, vim.log.levels.WARN)
        return
    end
    vim.fn.setqflist({}, "r", { title = "changes: " .. label, items = items })
    vim.cmd.copen()
end

--- A back-reference carries no text of its own, so it borrows the group's:
--- arriving at one should say what the finding is, not just its number. `↑` sits
--- next to the id rather than after the text, so it survives truncation -- it is
--- the only thing distinguishing a borrowed body from the site that owns it.
local function bodies_by_id()
    local bodies = {}
    for _, group in ipairs(grouped(marker_root())) do
        bodies[group.id] = { text = group.text, kind = group.kind }
    end
    return bodies
end

--- `[7]↑ fix` — id, borrowed-body arrow, kind. Front-loaded so the eye lands on
--- the finding rather than on a path.
local function label_of(marker, bodies)
    local kind = marker.kind or (bodies[marker.id] or {}).kind
    return string.format("[%d]%s%s", marker.id, marker.text and "" or "↑", kind and (" " .. kind) or "")
end

--- The AI's review order. `why` carries its reasoning into :copen, so the
--- ordering is inspectable while you walk it rather than being taken on faith.
function M.order()
    local path = review_dir() .. "/order.json"
    local file = io.open(path, "r")
    if not file then
        vim.notify("No review order yet — run /pr-session to analyse the PR", vim.log.levels.WARN)
        return
    end
    local raw = file:read("*a")
    file:close()
    local ok, decoded = pcall(vim.json.decode, raw)
    if not ok or type(decoded.entries) ~= "table" then
        vim.notify("Malformed order.json", vim.log.levels.ERROR)
        return
    end
    -- Context entries are flagged, never silently mixed in: the count of entries
    -- is how you judge the size of the change, so a file that is not part of it
    -- must not read like one.
    local items = {}
    for index, entry in ipairs(decoded.entries) do
        table.insert(items, {
            filename = M.root() .. "/" .. entry.file,
            lnum = entry.lnum or 1,
            text = string.format("%d.%s %s", index, entry.context and " (context)" or "", entry.why or ""),
        })
    end
    vim.fn.setqflist({}, "r", { title = "review order", items = items })
    vim.cmd.copen()
end

-- Colour carries the kind so a row reads without parsing: green ships, yellow
-- needs a decision, blue is a question, grey is private. Raw escapes so a row is
-- built by plain concatenation.
local ANSI = {
    fix = "\27[32m",
    ask = "\27[34m",
    note = "\27[90m",
    finding = "\27[33m",
    dim = "\27[90m",
    off = "\27[0m",
}

--- One row per site, since a back-reference is identifiable only by where it is.
---
--- The path leads the row because that is what the builtin previewer parses out of
--- it -- fzf substitutes the *displayed* text into the preview placeholder, so a
--- path hidden behind a delimiter and dropped from the display is a path the
--- preview cannot find. Dimming it and colouring the label carries the eye past it
--- instead: kind colour first, then the finding, with the text clipped so long
--- bodies cannot push everything else off the row.
function M.list()
    local markers = M.project_markers(marker_root())
    if #markers == 0 then
        vim.notify("No markers yet — run /pr-session for a draft, or <Leader>rc to write one", vim.log.levels.WARN)
        return
    end
    local root = M.root()
    local bodies = bodies_by_id()
    -- Half the picker width, less what the path and label already spend.
    local budget = math.max(30, math.floor(vim.o.columns * 0.45) - 34)
    local entries = {}
    for _, marker in ipairs(markers) do
        local label = label_of(marker, bodies)
        local kind = marker.kind or (bodies[marker.id] or {}).kind or "finding"
        local text = (bodies[marker.id] or {}).text or "(no body)"
        if vim.fn.strdisplaywidth(text) > budget then
            text = vim.fn.strcharpart(text, 0, budget - 1) .. "…"
        end
        table.insert(
            entries,
            table.concat({
                ANSI.dim,
                string.format("%s:%d:%d:", relative(marker.file, marker_root()), marker.lnum, marker.col),
                ANSI.off,
                " ",
                ANSI[kind] or ANSI.finding,
                label,
                ANSI.off,
                string.rep(" ", math.max(1, 11 - vim.fn.strdisplaywidth(label))),
                text,
            })
        )
    end
    fzf.fzf_exec(entries, {
        prompt = "markers> ",
        cwd = root,
        previewer = "builtin",
        winopts = { title = " review markers " },
        fzf_opts = { ["--ansi"] = true },
        -- One selection opens it; several become a quickfix list, which is how the
        -- marker set reaches the same surface the work list uses.
        actions = { ["default"] = fzf.actions.file_edit_or_qf },
    })
end

-- Report ------------------------------------------------------------------

--- Harvest the marker set into `.review/findings.md` and open it, excluding `note`
--- findings. Idempotent: the document is rewritten in full from the markers, with
--- `.review/summary.md` embedded ahead of them when analysis has written one.
---
--- Both the gate into the implement step and the way a review is read back after time
--- away, since re-harvesting costs nothing and the finding texts are what a context
--- switch erases. One document rather than two, so the prose introduces the findings
--- instead of competing with them, and so a markdown preview covers the whole review.
--- `note` markers are dropped here rather than at scan time: they still highlight and
--- navigate, they just never leave the worktree.
function M.report()
    -- Always the review worktree's, whichever tab this is run from: one findings.md
    -- per session, in the tree the markers live in.
    local root = marker_root()
    local dir = root .. "/.review"
    vim.fn.mkdir(dir, "p")
    -- The summary is analysis's to write and is embedded verbatim -- its own heading
    -- levels are the document's, so the harvested set sits under a peer heading. Absent
    -- one, the findings stand alone under their own title.
    local summary = vim.fn.filereadable(dir .. "/summary.md") == 1 and vim.fn.readfile(dir .. "/summary.md") or nil
    local index, detail = {}, {}
    local heading = summary and "###" or "##"
    if summary then
        vim.list_extend(index, summary)
        vim.list_extend(index, { "", "---", "", "## The findings", "" })
    else
        vim.list_extend(index, { "# Findings", "" })
    end
    local kept = 0
    local tally = { fix = 0, finding = 0, ask = 0, note = 0 }
    for _, group in ipairs(grouped(root)) do
        tally[group.kind or "finding"] = (tally[group.kind or "finding"] or 0) + 1
        if group.kind ~= "note" then
            kept = kept + 1
            local location = group.file and string.format("%s:%d", relative(group.file, root), group.lnum) or "?"
            table.insert(
                index,
                string.format("- **[%d]** %s — %s", group.id, group.kind or "finding", group.text or "(no body)")
            )
            table.insert(
                detail,
                string.format("%s [%d] %s — %s", heading, group.id, group.kind or "finding", location)
            )
            table.insert(detail, "")
            table.insert(detail, group.text or "(no body)")
            if #group.sites > 0 then
                table.insert(detail, "")
                table.insert(detail, "Also at:")
                for _, site in ipairs(group.sites) do
                    table.insert(detail, string.format("- %s:%d", relative(site.file, root), site.lnum))
                end
            end
            table.insert(detail, "")
        end
    end
    table.insert(index, "")
    local lines = vim.list_extend(index, detail)
    local path = dir .. "/findings.md"
    vim.fn.writefile(lines, path)
    vim.cmd.edit(vim.fn.fnameescape(path))
    -- The manifest is the gate: harvesting is the moment you commit the finding
    -- set to the expensive step, so what that step will act on is worth seeing.
    vim.notify(
        string.format(
            "%d findings → %s\n  %d to implement · %d to ask · %d private",
            kept,
            relative(path, root),
            tally.fix + tally.finding,
            tally.ask,
            tally.note
        )
    )
end

--- The marker set as markdown on the clipboard, grouped by file, for pasting into a PR
--- by hand.
---
--- For a review that goes somewhere other than the pull request it came from -- a Slack
--- thread, a message to the author, a note to yourself -- and for when the anchoring
--- `M.github_review` does is not wanted. Grouped by file and ordered by line, because that is the
--- order a GitHub diff is walked in -- a set grouped by finding would mean scrolling back
--- and forth for every entry.
---
--- `note` markers are dropped, as in `M.report`: they navigate and highlight, they just
--- never leave the worktree. `ask` markers are kept and marked, since a question is
--- exactly the thing worth pasting.
function M.clipboard()
    local root = marker_root()
    local by_file, order = {}, {}
    for _, group in ipairs(grouped(root)) do
        if group.kind ~= "note" and group.file then
            for _, site in ipairs(vim.list_extend({ { file = group.file, lnum = group.lnum } }, group.sites)) do
                local path = relative(site.file, root)
                if not by_file[path] then
                    by_file[path] = {}
                    table.insert(order, path)
                end
                table.insert(by_file[path], {
                    lnum = site.lnum,
                    kind = group.kind,
                    text = group.text or "(no body)",
                })
            end
        end
    end
    if #order == 0 then
        vim.notify("No findings to copy — write one with <Leader>rc first", vim.log.levels.WARN)
        return
    end
    table.sort(order)
    local lines, count = {}, 0
    for _, path in ipairs(order) do
        table.insert(lines, "## " .. path)
        table.insert(lines, "")
        table.sort(by_file[path], function(left, right)
            return left.lnum < right.lnum
        end)
        for _, entry in ipairs(by_file[path]) do
            count = count + 1
            -- `ask` is called out because it changes what the author is expected to do with
            -- the line; `fix` and a plain finding both read as "change this".
            local prefix = entry.kind == "ask" and "**Question** " or ""
            table.insert(lines, string.format("- **L%d** %s%s", entry.lnum, prefix, entry.text))
        end
        table.insert(lines, "")
    end
    local markdown = table.concat(lines, "\n")
    -- Both registers: `+` is what a browser paste reads, `"` makes it available to a
    -- put in this editor without a second key.
    vim.fn.setreg("+", markdown)
    vim.fn.setreg('"', markdown)
    vim.notify(string.format("%d finding site(s) across %d file(s) → clipboard", count, #order))
end

-- Posting a review to GitHub ----------------------------------------------
--
-- The mechanical exit from a skim: every finding becomes an inline comment on the line it
-- was written against, and the set goes up as one review carrying a verdict. `M.clipboard`
-- hands the same findings over as text to paste by hand; this puts them on the diff, where
-- the author reads code, and attaches the approval to them.
--
-- One review rather than a comment apiece, because a review is atomic -- one notification,
-- one page, one verdict -- and because a loose comment cannot approve anything.
--
-- Anchoring is what the conversion is actually about, and it needs two translations:
--
--   * A marker is an uncommitted insertion, so every line beneath one sits lower on disk
--     than in the commit GitHub anchors against. The diff against HEAD gives the shift.
--   * GitHub only accepts a comment on a line inside one of the pull request's own diff
--     hunks. A line outside them is a 422 that rejects the whole review, so a finding on
--     untouched code is folded into the summary rather than posted.

local REVIEW_VERBS = { APPROVE = "Approve", COMMENT = "Comment on", REQUEST_CHANGES = "Request changes on" }
-- Kind, rendered for the author. `note` never gets here; a plain finding needs no label,
-- since "change this" is what a review comment already means.
local REVIEW_LABEL = { ask = "Question", fix = "Suggestion" }
-- Everything from this line down is dropped on write. An HTML comment, so a body that
-- somehow keeps it renders as nothing on GitHub rather than as instructions to the author.
local CUT = "<!-- Everything from this line down is dropped when this buffer is written."
-- How far below a marker to look for a line that exists in the commit under review.
-- Markers stack when one line draws two findings; a stack deeper than this does not happen.
local ANCHOR_SEARCH = 10

--- The pull request the markers belong to, with what anchoring a comment in it needs, or
--- nil and a reason.
local function pr_context(root)
    root = root or marker_root()
    local state = read_json(root .. "/.review/skim.json") or read_json(root .. "/.review/session.json")
    if not (state and state.pr) then
        return nil, "no pull request is loaded here -- :PrDiff <pr> on the skim surface first"
    end
    local base = state.base or state.merge_base
    if not base then
        return nil, ("nothing records what #%s is being compared against"):format(state.pr)
    end
    -- The remote rather than `gh repo view`: the owner is in the URL already, and reading
    -- it locally costs no request and cannot be redirected by GH_REPO being set elsewhere.
    local origin = git({ "remote", "get-url", "origin" }, root)
    local owner, name = origin:match("github%.com[:/]([^/]+)/([^/]+)$")
    if not owner then
        return nil, ("origin is not a GitHub remote: %s"):format(origin)
    end
    local head, code = git({ "rev-parse", "HEAD" }, root)
    if code ~= 0 then
        return nil, ("%s is not a git worktree"):format(root)
    end
    return {
        root = root,
        pr = state.pr,
        title = state.title,
        slug = ("%s/%s"):format(owner, (name:gsub("%.git$", ""))),
        base = base,
        head = head,
        maps = {},
        hunks = {},
        lengths = {},
    }
end

--- Disk line to line in HEAD, for one file. Nil for a line HEAD does not have -- a marker,
--- or anything else edited in since.
local function head_line_map(root, path)
    local diff = git({ "diff", "--unified=0", "HEAD", "--", path }, root)
    local hunks = {}
    for old_count, new_start, new_count in diff:gmatch("@@ %-%d+,?(%d*) %+(%d+),?(%d*) @@") do
        table.insert(hunks, {
            old_count = tonumber(old_count) or 1,
            new_start = tonumber(new_start),
            new_count = tonumber(new_count) or 1,
        })
    end
    return function(line)
        local shift = 0
        for _, hunk in ipairs(hunks) do
            if line >= hunk.new_start and line < hunk.new_start + hunk.new_count then
                return nil
            end
            -- A hunk that only deletes names the line *before* the deletion, so its shift
            -- starts one line later than one that adds.
            if line >= hunk.new_start + math.max(hunk.new_count, 1) then
                shift = shift + hunk.old_count - hunk.new_count
            end
        end
        return line + shift
    end
end

local function to_head(context, path)
    context.maps[path] = context.maps[path] or head_line_map(context.root, path)
    return context.maps[path]
end

--- Whether GitHub will take a comment on this line: is it inside a hunk of the pull
--- request's own diff, context lines included.
---
--- Measured locally against the merge base, which is the same two revisions GitHub
--- diffs, rather than by fetching the pull request's files -- same hunks, no request.
local function in_pr_diff(context, path, line)
    if not context.hunks[path] then
        local ranges = {}
        local diff = git({ "diff", context.base, context.head, "--", path }, context.root)
        for new_start, new_count in diff:gmatch("@@ %-%d+,?%d* %+(%d+),?(%d*) @@") do
            local count = tonumber(new_count) or 1
            if count > 0 then
                table.insert(ranges, { first = tonumber(new_start), last = tonumber(new_start) + count - 1 })
            end
        end
        context.hunks[path] = ranges
    end
    for _, range in ipairs(context.hunks[path]) do
        if line >= range.first and line <= range.last then
            return true
        end
    end
    return false
end

local function disk_length(context, path)
    context.lengths[path] = context.lengths[path] or #vim.fn.readfile(context.root .. "/" .. path)
    return context.lengths[path]
end

--- The line a finding is about, in the commit under review. Markers sit above the code they
--- annotate, so the anchor is the first line below the marker that exists in that commit --
--- past the marker itself, and past any marker stacked on the same line.
local function anchor_line(context, path, lnum)
    local map = to_head(context, path)
    for candidate = lnum, math.min(lnum + ANCHOR_SEARCH, disk_length(context, path)) do
        local head = map(candidate)
        if head then
            return head
        end
    end
    return nil
end

--- Every finding as a review comment, split into the ones GitHub will accept and the ones
--- it will not.
---
--- One comment per site rather than per finding: a back-reference exists precisely because
--- the finding shows up somewhere else too, and collapsing those into a list of paths in
--- one comment puts the author back to scrolling. Each carries the finding's id, so a group
--- reads as a group on a page that renders comments file by file -- the cheap form of a
--- link between them, and the one that survives GitHub collapsing an outdated comment.
local function review_comments(context)
    local accepted, orphans = {}, {}
    for _, group in ipairs(grouped(context.root)) do
        if group.kind ~= "note" and group.file then
            local sites = {}
            for index, site in ipairs(vim.list_extend({ { file = group.file, lnum = group.lnum } }, group.sites)) do
                local path = relative(site.file, context.root)
                local line = anchor_line(context, path, site.lnum)
                table.insert(sites, {
                    path = path,
                    line = line,
                    lnum = site.lnum,
                    primary = index == 1,
                    postable = line ~= nil and in_pr_diff(context, path, line),
                })
            end
            -- Where else the finding sits, so the primary comment says so without needing a
            -- link. Only postable sites: an entry pointing at a line the author cannot open
            -- from the diff page is worse than no entry.
            local elsewhere, first = {}, nil
            for _, site in ipairs(sites) do
                if site.postable then
                    first = first or ("`%s:%d`"):format(site.path, site.line)
                    if not site.primary then
                        table.insert(elsewhere, ("`%s:%d`"):format(site.path, site.line))
                    end
                end
            end
            local text = group.text or "(no body)"
            for _, site in ipairs(sites) do
                -- `[3] ↑ Question` -- the id first, since it is what ties the group together
                -- on a page that renders comments file by file.
                local label = ("[%d]%s%s"):format(
                    group.id,
                    site.primary and "" or " ↑",
                    REVIEW_LABEL[group.kind] and " " .. REVIEW_LABEL[group.kind] or ""
                )
                local body = { ("**%s** %s"):format(label, text) }
                if site.primary and #elsewhere > 0 then
                    table.insert(body, "")
                    table.insert(body, "Also at " .. table.concat(elsewhere, ", ") .. ".")
                elseif not site.primary and first then
                    table.insert(body, "")
                    table.insert(body, "Same finding as " .. first .. ".")
                end
                local entry = {
                    label = label,
                    path = site.path,
                    line = site.line or site.lnum,
                    text = text,
                    body = table.concat(body, "\n"),
                }
                table.insert(site.postable and accepted or orphans, entry)
            end
        end
    end
    local function by_position(left, right)
        if left.path ~= right.path then
            return left.path < right.path
        end
        return left.line < right.line
    end
    table.sort(accepted, by_position)
    table.sort(orphans, by_position)
    return accepted, orphans
end

--- What the buffer holds above the cut, as the review body.
local function summary_of(bufnr)
    local lines = {}
    for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
        if line:find(CUT, 1, true) then
            break
        end
        table.insert(lines, line)
    end
    return vim.trim(table.concat(lines, "\n"))
end

--- The block under the cut: the verdict, and every comment the write will post, at the line
--- it will land on. The one chance to see the anchoring before the author does.
local function preview_lines(context, event, accepted, orphans)
    local lines = {
        CUT,
        ("%s %s#%s at %s."):format(REVIEW_VERBS[event], context.slug, context.pr, context.head:sub(1, 7)),
        "",
        ":wq posts. :q! abandons. An empty summary posts nothing.",
        "The comment set below is recomputed on write, so a finding written after this",
        "block was drawn still goes up.",
        "",
    }
    local function render(entry)
        table.insert(
            lines,
            ("  %s:%d  %s %s"):format(
                entry.path,
                entry.line,
                entry.label,
                #entry.text > 64 and entry.text:sub(1, 63) .. "…" or entry.text
            )
        )
    end
    table.insert(lines, ("%d inline comment(s):"):format(#accepted))
    for _, entry in ipairs(accepted) do
        render(entry)
    end
    if #orphans > 0 then
        table.insert(lines, "")
        table.insert(lines, ("%d finding(s) sit on lines this PR does not touch, which GitHub"):format(#orphans))
        table.insert(lines, "will not anchor a comment to. They are appended to the summary instead:")
        for _, entry in ipairs(orphans) do
            render(entry)
        end
    end
    table.insert(lines, "-->")
    return lines
end

--- Findings GitHub refused to anchor, carried in the body so they are still said.
local function orphan_section(orphans)
    if #orphans == 0 then
        return ""
    end
    -- Two blank lines ahead of the rule, or markdown reads `---` as an underline and turns
    -- the summary's last line into a heading.
    local lines = { "", "", "---", "", "On lines this pull request does not change:", "" }
    for _, entry in ipairs(orphans) do
        table.insert(lines, ("- `%s:%d` — **%s** %s"):format(entry.path, entry.line, entry.label, entry.text))
    end
    return table.concat(lines, "\n")
end

--- Post, and report what the author will see. Failure leaves the draft alone and the buffer
--- modified, which is what stops `:wq` from closing a window over an unposted review.
local function post_review(bufnr)
    local context, reason = pr_context(vim.b[bufnr].review_root)
    if not context then
        return vim.notify("Review: " .. reason, vim.log.levels.ERROR)
    end
    local event = vim.b[bufnr].review_event
    local summary = summary_of(bufnr)
    if summary == "" then
        return vim.notify("Review: empty summary, nothing posted", vim.log.levels.WARN)
    end

    local accepted, orphans = review_comments(context)
    local comments = {}
    for _, entry in ipairs(accepted) do
        -- RIGHT is the head side of the diff, which is the only side a marker can sit on:
        -- markers are written into the files as they are after the change.
        table.insert(comments, { path = entry.path, line = entry.line, side = "RIGHT", body = entry.body })
    end
    local payload = {
        commit_id = context.head,
        event = event,
        body = summary .. orphan_section(orphans),
    }
    if #comments > 0 then
        payload.comments = comments
    end

    local result = vim.system({
        "gh",
        "api",
        "--method",
        "POST",
        ("repos/%s/pulls/%s/reviews"):format(context.slug, context.pr),
        "--input",
        "-",
        "--jq",
        ".html_url",
    }, { cwd = context.root, stdin = vim.json.encode(payload), text = true }):wait()

    if result.code ~= 0 then
        return vim.notify(
            ("Review: GitHub rejected the review, nothing was posted -- %s"):format(
                vim.trim(result.stderr or ""):gsub("\n", " ")
            ),
            vim.log.levels.ERROR
        )
    end

    vim.notify(
        ("Review: %s posted on #%s — %d inline comment(s), %d in the summary\n%s"):format(
            event,
            context.pr,
            #comments,
            #orphans,
            vim.trim(result.stdout or "")
        )
    )
    -- Written: the buffer stops being modified, so a `:wq` closes its window. Then wiped,
    -- because a draft that has been posted is the one thing that must not be posted twice.
    vim.bo[bufnr].modified = false
    vim.schedule(function()
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end)
end

--- Compose a review of the loaded pull request and post it on write.
---
--- A buffer rather than a prompt, because a summary is prose and because the list under the
--- cut is where the anchoring gets checked. One draft per pull request, whatever the
--- verdict: re-running any of the three commands sets the verdict and redraws the block,
--- leaving what you have already written alone.
function M.github_review(event)
    local context, reason = pr_context()
    if not context then
        return vim.notify("Review: " .. reason, vim.log.levels.ERROR)
    end
    local accepted, orphans = review_comments(context)

    local name = ("GithubReview://%s/%s"):format(context.slug, context.pr)
    local bufnr
    for _, candidate in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(candidate) == name then
            bufnr = candidate
        end
    end
    -- `:q!` on the draft discards it, which unloads the buffer and leaves the name taken by
    -- something that reads back as empty. Start over rather than write into the corpse.
    if bufnr and not vim.api.nvim_buf_is_loaded(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
        bufnr = nil
    end
    local summary = bufnr and summary_of(bufnr) or ""

    if not bufnr then
        bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(bufnr, name)
        vim.bo[bufnr].buftype = "acwrite"
        vim.bo[bufnr].filetype = "markdown"
        -- Kept loaded when its window closes, so `:q!` abandons the posting without
        -- discarding what was written: run the command again and the draft is still there.
        -- The default unloads it, and an unloaded buffer reads back as empty.
        vim.bo[bufnr].bufhidden = "hide"
        vim.api.nvim_create_autocmd("BufWriteCmd", {
            buffer = bufnr,
            callback = function()
                post_review(bufnr)
            end,
        })
    end
    -- The worktree is captured now: at write time the current buffer is this one, whose
    -- name is no path, so nothing can be walked upward from it.
    vim.b[bufnr].review_root = context.root
    vim.b[bufnr].review_event = event

    local lines = vim.split(summary, "\n")
    table.insert(lines, "")
    vim.list_extend(lines, preview_lines(context, event, accepted, orphans))
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modified = true

    if vim.api.nvim_get_current_buf() ~= bufnr then
        vim.cmd("botright split")
        vim.api.nvim_win_set_buf(0, bufnr)
    end
    vim.api.nvim_win_set_cursor(0, { #vim.split(summary, "\n"), 0 })
end

-- Highlighting ------------------------------------------------------------

-- Green ships, yellow needs a decision, blue is a question, dim is private.
vim.api.nvim_set_hl(0, "ReviewMarker", { link = "DiagnosticWarn", default = true })
vim.api.nvim_set_hl(0, "ReviewMarkerFix", { link = "DiagnosticOk", default = true })
vim.api.nvim_set_hl(0, "ReviewMarkerAsk", { link = "DiagnosticInfo", default = true })
vim.api.nvim_set_hl(0, "ReviewMarkerNote", { link = "Comment", default = true })

--- Extmarks rather than matchadd: a marker belongs to the buffer, not the
--- window, so it has to survive a split. A full rescan is a plain substring
--- search per line, cheap enough that debouncing would be premature.
local function refresh(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
    for _, marker in ipairs(M.buffer_markers(bufnr)) do
        vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, marker.lnum - 1, marker.col - 1, {
            end_col = marker.line_length,
            hl_group = highlight_group(marker),
        })
    end
end

vim.api.nvim_create_autocmd({ "BufWinEnter", "TextChanged", "InsertLeave", "BufWritePost" }, {
    callback = function(event)
        refresh(event.buf)
    end,
})

-- Bindings ----------------------------------------------------------------

local function map(keys, fn, desc)
    vim.keymap.set("n", keys, fn, { desc = desc })
end

map("<Leader>rc", function()
    M.insert()
end, "Review: new finding")
map("<Leader>rf", function()
    M.insert("fix")
end, "Review: new fix")
map("<Leader>ra", function()
    M.insert("ask")
end, "Review: new question")
map("<Leader>rn", function()
    M.insert("note")
end, "Review: new private note")
map("<Leader>rr", M.link, "Review: link to an existing finding")
map("<Leader>rl", M.list, "Review: list findings")
-- One work-list key, whose contents follow the worktree and the scope: the PR's hunks
-- while reading, the suggestion's while accepting. Findings are a different question,
-- answered by the marker list -- whose multi-select lands in this same quickfix list,
-- so markers need no key of their own.
map("<Leader>rq", M.hunks, "Review: the change as a work list")
map("<Leader>ro", M.order, "Review: order to quickfix")
map("<Leader>rd", M.delete, "Review: delete marker")
map("<Leader>rw", M.report, "Review: write findings.md")
map("<Leader>rY", M.clipboard, "Review: copy findings as markdown")
map("¨r", function()
    M.jump(1)
end, "Review: next marker")
map("år", function()
    M.jump(-1)
end, "Review: previous marker")
map("<Leader>rt", M.status, "Review: finding states")
map("<Leader>rj", M.demo, "Review: same place in the other worktree")
map("<Leader>rb", M.toggle_scope, "Review: this round, or the whole suggestion")
map("<Leader>rp", M.panel, "Review: where the session stands")
map("<Leader>rD", M.diff, "Review: browse the change")

vim.api.nvim_create_user_command("ReviewOrder", M.order, { desc = "Load the review order into the quickfix list" })
vim.api.nvim_create_user_command("ReviewReport", M.report, { desc = "Harvest markers into .review/findings.md" })
vim.api.nvim_create_user_command("ReviewCopy", M.clipboard, { desc = "Copy findings as markdown for a PR comment" })
-- Three commands rather than one with an argument, because the verdict is the whole
-- decision being made and typing it out is the moment to make it.
vim.api.nvim_create_user_command("GithubApprove", function()
    M.github_review("APPROVE")
end, { desc = "Approve the loaded PR, posting the markers as inline comments" })
vim.api.nvim_create_user_command("GithubComment", function()
    M.github_review("COMMENT")
end, { desc = "Comment on the loaded PR, posting the markers as inline comments" })
vim.api.nvim_create_user_command("GithubRequestChanges", function()
    M.github_review("REQUEST_CHANGES")
end, { desc = "Request changes on the loaded PR, posting the markers as inline comments" })
vim.api.nvim_create_user_command("Review", M.panel, { desc = "Where the session stands and what to do next" })
vim.api.nvim_create_user_command("ReviewStatus", M.status, { desc = "Findings and their states" })
vim.api.nvim_create_user_command("ReviewDiff", M.diff, { desc = "Browse the whole change in a file panel" })
vim.api.nvim_create_user_command("ReviewHunks", M.hunks, { desc = "The change as a quickfix work list" })
vim.api.nvim_create_user_command("ReviewDemo", M.demo, { desc = "Same file and line in the other worktree" })
vim.api.nvim_create_user_command("ReviewAccept", function(opts)
    M.accept(opts.fargs[1], opts.bang)
end, {
    nargs = "?",
    bang = true,
    desc = "Commit the staged changes as accepted finding <id>, or `docs` (! takes the whole change)",
    complete = function()
        local session = M.session()
        if not session then
            return {}
        end
        local done, ids = landed(session), {}
        for _, group in ipairs(grouped(session.review_worktree)) do
            if group.kind ~= "note" and group.kind ~= "ask" and not done[group.id] then
                table.insert(ids, tostring(group.id))
            end
        end
        -- Offered only when there is something to accept, so it never suggests committing
        -- an empty documentation pass.
        local staged_count, unstaged_count = uncommitted(session)
        if staged_count + unstaged_count > 0 then
            table.insert(ids, "docs")
        end
        return ids
    end,
})
