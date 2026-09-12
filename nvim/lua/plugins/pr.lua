-- Reading a pull request without a review session: the org-wide PR list, loading one
-- into this worktree, and the three surfaces over the change it sets up.
--
-- The quick end of reviewing. A session (see review.lua and docs/pr-review.md) pins two
-- worktrees to one PR and ships its findings as commits; that is the right shape when a
-- PR deserves hours, and far too much ceremony when it deserves ten minutes. This is the
-- ten-minute shape: one worktree that moves from PR to PR, markers if you want them, and
-- findings that leave as one posted review rather than as commits -- see review.lua's
-- `:GithubApprove`, which anchors each marker on the line it was written against.
--
--   :PrList / <Leader>hl   every open PR in the organisation, review-requested first, with
--                          the description rendered beside the list (! or ctrl-l re-fetches)
--   :PrDiff <pr|url>       load one into this worktree
--   <Leader>hf             which changed file? -- fuzzy, diff in the preview
--   <Leader>hD             how big is this? -- every changed file, side by side
--   <Leader>hd, ¨h, åh     one file against the base, then hunk by hunk
--   :DiffBase [<ref>]      sign the files against a ref, or against the resolved base
--                          with no argument ('off' goes back to the index)
--   <Leader>hb             what does the author say this is? -- the loaded PR's description
--   <Leader>hw             move to another worktree, picked by branch -- then ask again
--
-- The two surfaces over the change work without a PR loaded at all: with no base named
-- they fall back to the merge base with the default branch, so `nvim` in an ordinary
-- checkout answers "what has this branch changed" with the same keys. See `pr_base`.
-- What the base currently is stays visible without running any of the above -- see
-- `render_diff_tag`.
--
-- Loading a PR fails silently when done by hand, which is what most of this file is
-- about. The working tree has to sit at the PR's head, or the signs describe whatever
-- branch is checked out instead. The base has to be the *merge base*, because gitsigns
-- diffs two revisions directly: naming the target branch signs everything that landed on
-- it since the PR forked, as reversed hunks in files the PR never touched. And a
-- revision absent from the repository yields zero hunks and no error at all, which looks
-- exactly like a PR that changed nothing -- so loading reports the file count it expects
-- you to see, and warns when that count is zero.

local fzf = require("fzf-lua")

local PR = {}

local function capture(cmd, cwd)
    local result = vim.system(cmd, { cwd = cwd, text = true }):wait()
    return vim.trim(result.stdout or ""), result.code, vim.trim(result.stderr or "")
end

local function warn(message)
    vim.notify("PR: " .. message, vim.log.levels.ERROR)
end

--- The git worktree the surfaces below answer for.
---
--- The buffer's own, so a file opened from one checkout is always measured against that
--- checkout's base rather than whichever one the editor happens to sit in. Except when
--- the working directory has been moved to a *different* worktree, which is the one case
--- the buffer cannot speak for: arriving somewhere and asking what changed there has to
--- answer about there, not about the file left open behind you.
---
--- A path test cannot stand in for either question: linked worktrees live under
--- `.worktrees/` inside the main checkout, so one worktree's path is a prefix of the
--- other's and prefixes prove nothing. Both are resolved with git or not at all.
local function worktree_root()
    local function toplevel(dir)
        if not dir or dir == "" or vim.fn.isdirectory(dir) == 0 then
            return nil
        end
        local root, code = capture({ "git", "rev-parse", "--show-toplevel" }, dir)
        return code == 0 and root ~= "" and root or nil
    end

    local cwd = vim.uv.cwd()
    local dir = vim.fn.expand("%:p:h")
    if dir == "" or dir == cwd then
        return toplevel(cwd)
    end
    local here, buffer = toplevel(cwd), toplevel(dir)
    if here and buffer and here ~= buffer then
        return here
    end
    return buffer or here
end

--- The main checkout, reached from any of its linked worktrees. Its name is the
--- repository's, and its parent holds the sibling clones -- which is how a PR in another
--- repository is located without configuring a list of paths anywhere.
local function main_root(cwd)
    local common, code = capture({ "git", "rev-parse", "--path-format=absolute", "--git-common-dir" }, cwd)
    if code ~= 0 then
        return nil
    end
    return vim.fs.dirname(common)
end

--- One row per `git worktree list --porcelain` block. Porcelain over the human-readable
--- form because a worktree path can contain spaces and the human form has no delimiter.
local function list_worktrees(root)
    local raw = capture({ "git", "worktree", "list", "--porcelain" }, root)
    local trees, current = {}, nil
    for line in (raw .. "\n"):gmatch("(.-)\n") do
        if line == "" then
            current = nil
        else
            local key, value = line:match("^(%S+)%s*(.*)$")
            if key == "worktree" then
                current = { path = value }
                table.insert(trees, current)
            elseif current and key == "branch" then
                current.branch = value:gsub("^refs/heads/", "")
            elseif current and key == "HEAD" then
                current.head = value
            end
        end
    end
    return trees
end

-- Skim surface ------------------------------------------------------------
--
-- `.review/skim.json` is written by `review skim` and rewritten here on every load. Its
-- presence is the surface's identity, which decides the one thing that differs from
-- loading a PR anywhere else: here the checkout is detached, because the reviewer is
-- frequently the PR's author and a branch already checked out in the main worktree
-- cannot be checked out again.
--
-- It also carries the current PR, so closing the editor does not lose the position --
-- the checkout survives on its own but the sign comparison does not.

local function skim_file(root)
    return (root or worktree_root() or "") .. "/.review/skim.json"
end

--- The `.review/` state the three PR surfaces record, as one table rather than one local
--- per accessor.
---
--- Deliberately a table: every lua file in this configuration is concatenated into a
--- single chunk, so top-level locals all share one function scope and Lua caps that at
--- 200. The count sits close enough to the ceiling that a handful of new ones stops the
--- whole configuration loading, and `nix build` cannot catch it -- it never runs the lua.
local state = {}

function state.read(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local raw = file:read("*a")
    file:close()
    local ok, decoded = pcall(vim.json.decode, raw)
    return ok and decoded or nil
end

--- Which PR an ordinary worktree is reading. The skim surface and a review session both
--- record one already; this covers the case neither does, so all three can answer the
--- same question. Alongside them rather than in a cache directory: `.review/` is ignored,
--- one directory answers "which PR is this", and nothing here can be committed.
function state.loaded_file(root)
    return (root or worktree_root() or "") .. "/.review/loaded.json"
end

function state.write_loaded(root, loaded)
    vim.fn.mkdir(vim.fs.dirname(state.loaded_file(root)), "p")
    local file = io.open(state.loaded_file(root), "w")
    if not file then
        return
    end
    file:write(vim.json.encode(loaded))
    file:close()
end

--- The pull request this worktree is reading, as `{ repo = , number = }`, or nil.
---
--- Three surfaces record one, and they are tried most-specific first: a review session
--- pins a worktree to a PR for its whole life, a skim surface moves from PR to PR, and an
--- ordinary worktree only knows what was last loaded into it. A session's record outranks
--- the others because its worktree cannot hold a different PR than the one it was built
--- for.
function state.current_pr(root)
    -- Paths rather than decoded states: an absent file decodes to nil, and a nil early in
    -- a table constructor ends the iteration rather than being skipped over. Reading
    -- lazily also stops at the first surface that answers.
    local files = {
        (root or "") .. "/.review/session.json",
        skim_file(root),
        state.loaded_file(root),
    }
    for _, path in ipairs(files) do
        local recorded = state.read(path)
        if recorded and recorded.pr and recorded.repo then
            return { repo = recorded.repo, number = tonumber(recorded.pr) }
        end
    end
    return nil
end

local function skim_state(root)
    return state.read(skim_file(root))
end

local function write_skim_state(root, state)
    local file = io.open(skim_file(root), "w")
    if not file then
        return
    end
    file:write(vim.json.encode(state))
    file:close()
end

-- Statusline --------------------------------------------------------------
--
-- Which PR is on screen, permanently rather than behind a key. The surface holds one PR
-- at a time and every other key reads it, so a filename alone never says what you are
-- looking at -- and unlike a session, this changes several times an hour.
--
-- Captured once: this prepends to the statusline, so re-rendering off an already
-- rendered value would stack tags on every refresh. review.lua does the same for a
-- session's roles, and the two never both apply -- the skim worktree has no session.
vim.api.nvim_set_hl(0, "PrTag", { link = "DiagnosticInfo", default = true })
vim.api.nvim_set_hl(0, "PrTagWarn", { link = "DiagnosticError", default = true })

local statusline_base = nil

local function render_pr_tag(state)
    statusline_base = statusline_base or vim.o.statusline
    if not (state and state.pr) then
        vim.opt.statusline = statusline_base
        return
    end
    vim.opt.statusline = string.format("%%#PrTag# SKIM · #%s %%* ", state.pr) .. statusline_base
end

-- Forward-declared: PR.load renders it below, but the function body needs `resolve_base`,
-- defined further down once the worktree it is about is in scope.
local render_diff_tag

-- Forward-declared for the same reason: PR.load caches a description, and the cache lives
-- with the listing that first needed it.
local write_body
local body_path

-- Loading a PR ------------------------------------------------------------

--- The PR number out of `339`, `#339`, or any GitHub pull-request URL.
local function pr_number(input)
    return input:match("^%s*#?(%d+)%s*$") or input:match("/pull/(%d+)")
end

--- Buffers from the PR being left behind. Wiped rather than reloaded: a file the next PR
--- does not contain would otherwise sit there showing content that is no longer on disk.
local function wipe_file_buffers()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[bufnr].buflisted and vim.api.nvim_buf_get_name(bufnr) ~= "" then
            pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
        end
    end
end

--- Back to the automatic merge base: shared by `:PrDiff off` and `:DiffBase` with no
--- argument, the two doors out of an explicitly named base.
local function reset_diff_base()
    require("gitsigns").reset_base(true)
    -- Cleared rather than left standing: with it set, the surfaces would keep
    -- answering with a base the sign column has already stopped signing against.
    vim.env.REVIEW_BASE = nil
    vim.env.REVIEW_BASE_DIR = nil
    vim.env.REVIEW_BASE_LABEL = nil
end

--- Put this worktree at a PR's head and sign its changes against the merge base.
---
--- On the skim surface the checkout is detached at a ref of our own, so no local branch
--- accumulates and nothing collides with the author's own branch. Anywhere else it is
--- `gh pr checkout`, which leaves a branch you can build on.
---
--- Returns the merge base on success, so a caller can chain a surface onto it.
function PR.load(input)
    local root = worktree_root()
    if not root then
        return warn("not inside a git worktree")
    end

    if input:match("^%s*off%s*$") then
        reset_diff_base()
        local skim = skim_state(root)
        if skim then
            skim.pr = nil
            write_skim_state(root, skim)
        end
        os.remove(state.loaded_file(root))
        render_diff_tag()
        vim.notify("PR: base back to the index")
        return nil
    end

    local number = pr_number(input)
    if not number then
        return warn(("expected a PR number or a pull-request URL, got %q"):format(input))
    end

    -- The description fields ride along rather than costing a second request later: every
    -- PR loaded by any path is cached from that moment, so reading its body is a local
    -- file open instead of a round trip.
    local raw, code, stderr = capture({
        "gh",
        "pr",
        "view",
        number,
        "--json",
        "title,headRefOid,baseRefName,headRefName,body,url,author,updatedAt,isDraft",
    }, root)
    if code ~= 0 then
        return warn(("gh could not read PR #%s in %s -- %s"):format(number, root, stderr))
    end
    local ok, pr = pcall(vim.json.decode, raw)
    if not ok then
        return warn("could not parse the gh response")
    end

    local skim = skim_state(root)

    -- Already on disk, one directory away. A PR whose head branch is checked out in a
    -- worktree of this repository cannot be checked out again -- git refuses a branch in
    -- two worktrees at once -- and does not need to be: the change is there to read. That
    -- covers every PR raised from a worktree still being worked in, which is the case
    -- reaching for a PR number is least able to handle otherwise.
    --
    -- Not on the skim surface, whose whole purpose is a detached checkout of someone
    -- else's work in a tree of its own.
    if not skim and capture({ "git", "branch", "--show-current" }, root) ~= pr.headRefName then
        for _, tree in ipairs(list_worktrees(root)) do
            if tree.branch == pr.headRefName and tree.path ~= root and vim.fn.isdirectory(tree.path) == 1 then
                vim.cmd(("lcd %s"):format(vim.fn.fnameescape(tree.path)))
                vim.notify(("PR: #%s is checked out at %s -- moved there"):format(number, tree.path))
                root = tree.path
                break
            end
        end
    end

    -- The author's own worktree: the PR's branch is already checked out here, so there is
    -- nothing to check out and nothing the dirty guard below protects. HEAD may sit ahead
    -- of the pushed tip -- unpushed commits are still the PR from the author's seat, and
    -- what is on disk is what wants signing.
    local author_here = capture({ "git", "branch", "--show-current" }, root) == pr.headRefName
    if not author_here and capture({ "git", "rev-parse", "HEAD" }, root) ~= pr.headRefOid then
        -- Markers are uncommitted edits, so tracked modifications are usually findings not
        -- yet pasted anywhere. Never discarded silently, and never stashed on the
        -- reviewer's behalf either -- both lose work in a way that is hard to notice.
        --
        -- Tracked only. Preparing a worktree leaves untracked furniture behind it -- a
        -- symlinked dependency tree, copied tool config, `.review/` -- which is present
        -- permanently, is not a finding, and would not be touched by the checkout below
        -- anyway. Counting it made every switch stop on a prompt about nothing.
        local dirty = capture({ "git", "status", "--porcelain", "--untracked-files=no" }, root)
        if dirty ~= "" then
            local files = #vim.split(dirty, "\n", { trimempty = true })
            if not skim then
                return warn(("%s has uncommitted changes -- commit or stash before loading #%s"):format(root, number))
            end
            local choice = vim.fn.confirm(
                ("%d file(s) here carry uncommitted edits.\nDiscard them and load PR #%s?"):format(files, number),
                "&Discard\n&Cancel",
                2,
                "Question"
            )
            if choice ~= 1 then
                return nil
            end
        end

        -- The PR's head at a ref outside refs/heads, so it never appears in a branch
        -- listing and never competes with a local branch of the same name. Returns what
        -- went wrong, or nil.
        local function detach_at_head()
            local ref = "refs/skim/" .. number
            local _, fetch_code, fetch_error = capture(
                { "git", "fetch", "--quiet", "--force", "origin", ("pull/%s/head:%s"):format(number, ref) },
                root
            )
            if fetch_code ~= 0 then
                return ("could not fetch pull/%s/head -- %s"):format(number, fetch_error)
            end
            local _, checkout_code, checkout_error = capture({ "git", "checkout", "--detach", "--force", ref }, root)
            if checkout_code ~= 0 then
                return ("could not check out #%s -- %s"):format(number, checkout_error)
            end
            return nil
        end

        if skim then
            local failure = detach_at_head()
            if failure then
                return warn(failure)
            end
        else
            local _, checkout_code, checkout_error = capture({ "gh", "pr", "checkout", number }, root)
            if checkout_code ~= 0 then
                -- `gh pr checkout` insists on a local branch, which git refuses when the
                -- name is taken. Detached reads the same revision and collides with
                -- nothing; what it gives up is committing on top, which is not what a
                -- number typed into a diff key was asking for. Reported rather than done
                -- silently, since the difference matters the moment you try.
                if detach_at_head() then
                    return warn(("could not check out #%s -- %s"):format(number, checkout_error))
                end
                vim.notify(("PR: #%s read detached -- %s"):format(number, checkout_error))
            end
        end
    end

    capture({ "git", "fetch", "--quiet", "origin", pr.baseRefName }, root)
    local target = "origin/" .. pr.baseRefName
    local base, base_code = capture({ "git", "merge-base", target, "HEAD" }, root)
    if base_code ~= 0 or base == "" then
        return warn(("no merge base between %s and the head of #%s"):format(target, number))
    end

    local repo_name = vim.fs.basename(main_root(root) or root)

    local changed = capture({ "git", "diff", "--name-only", base, "HEAD" }, root)
    local count = #vim.split(changed, "\n", { trimempty = true })

    if skim then
        wipe_file_buffers()
        skim.pr = tonumber(number)
        skim.title = pr.title
        skim.base = base
        write_skim_state(root, skim)
    else
        -- An ordinary worktree keeps no record of its own, so nothing else could answer
        -- which PR is on screen -- not the statusline, and not the description key.
        state.write_loaded(root, { repo = repo_name, pr = tonumber(number), title = pr.title })
    end

    -- The cache is keyed on both, and `gh pr view` reports neither: the repository is this
    -- checkout's own, and the number is the one that was asked for.
    pr.repository = { name = repo_name }
    pr.number = tonumber(number)
    write_body(pr)

    -- All three, always together: the sign column and the surfaces over the change read
    -- different variables, and one of them left behind is a panel describing the PR that
    -- was loaded before this one. The worktree the base belongs to travels with it, so
    -- an editor started from here in another worktree does not inherit an answer about
    -- this one.
    require("gitsigns").change_base(base, true)
    vim.env.REVIEW_BASE = base
    vim.env.REVIEW_BASE_DIR = root
    vim.env.REVIEW_BASE_LABEL = pr.baseRefName
    render_diff_tag()
    -- The checkout rewrote files under any buffer still open on them.
    vim.cmd("checktime")

    if count == 0 then
        warn(
            ("#%s: %s -- no changed files against %s, so there is nothing to sign"):format(
                number,
                pr.title,
                base:sub(1, 7)
            )
        )
        return nil
    end
    vim.notify(
        ("PR #%s: %s\n%d changed file%s, signed against %s"):format(
            number,
            pr.title,
            count,
            count == 1 and "" or "s",
            base:sub(1, 7)
        )
    )
    return base
end

-- Surfaces over the change ------------------------------------------------

--- The revision the surfaces below measure against, resolved at the keypress rather than
--- held anywhere -- because most of the time the question is asked in a checkout nobody
--- ran `:PrDiff` in, and a base captured at startup would have nothing to say there.
---
--- `$REVIEW_BASE` first. It is where a base that cannot be worked out from the
--- repository alone gets stated: a stacked PR's base is the branch below it, not the
--- default branch. `review` and `review skim` export it, loading a PR rewrites it, and
--- setting it by hand overrides both.
---
--- Then the merge base with the default branch, which is what "what did this branch
--- change" means outside a review. On the default branch itself that is HEAD and the
--- comparison is empty, which is the honest answer rather than a failure.
---
--- Only then the base gitsigns is signing against, which is the answer while a PR is
--- loaded in a repository with no reachable default branch at all.
---
--- Takes the worktree explicitly rather than resolving its own -- a picker over another
--- worktree (the file panel for someone else's checkout, an agent's) needs this same
--- order applied to a directory that is not the one the current buffer sits in.
---
--- No side effects: never warns, never touches the environment. A passive caller (the
--- statusline tag, a picker listing several worktrees at once) runs this on every
--- refresh, and a notification firing on every one of those for the unremarkable case of
--- "nothing loaded" would be noise, not signal. `pr_base` below adds the warning back for
--- the keys that act on the answer immediately, where silence would look like "nothing
--- changed" rather than "no base could be found".
---
--- Returns the target alongside the base, so a caller that displays the answer can say
--- what it resolved against rather than a bare commit.
local function resolve_base(root)
    -- An environment variable is inherited by every descendant process, so a base minted
    -- for one worktree reaches an editor started from a `:terminal` in another one -- and
    -- there the commit still resolves, out of the same object database, so the wrong
    -- answer arrives without an error. REVIEW_BASE_DIR is the worktree the base was minted
    -- for, and a mismatch means this base is not about the code on screen.
    --
    -- Absent, the base is trusted: that is a base exported by hand, which is the supported
    -- way to name one nothing else can work out.
    if vim.env.REVIEW_BASE and vim.env.REVIEW_BASE ~= "" then
        local minted_for = vim.env.REVIEW_BASE_DIR
        if minted_for == nil or minted_for == "" or minted_for == root then
            -- A commit alone cannot say which ref it was named as, and "base@<sha>" is a
            -- worse answer to "what am I diffing against" than the branch name whoever
            -- minted it already had. Carried beside the sha rather than recovered from it.
            local named = vim.env.REVIEW_BASE_LABEL
            return vim.env.REVIEW_BASE, (named ~= "" and named or nil)
        end
    end

    if root then
        -- origin/HEAD is the default branch wherever the clone recorded one; the two
        -- names after it are for a clone where it was never set, which is most clones
        -- made by `git clone --depth` or by tooling.
        --
        -- Read as the clone last left it, never fetched: this runs on a keypress, and a
        -- network round trip per keypress is not worth paying. The ceiling is that the
        -- base is as old as the last fetch -- which shows up as a diff carrying commits
        -- that have since landed on the default branch. `git fetch` is the fix.
        for _, target in ipairs({ "origin/HEAD", "origin/main", "origin/master" }) do
            local base, code = capture({ "git", "merge-base", "HEAD", target }, root)
            if code == 0 and base ~= "" then
                -- "origin/HEAD" is a symbolic ref, not a branch -- displaying it literally
                -- would read as "diffed against itself". Resolve what it points to instead.
                if target == "origin/HEAD" then
                    local resolved = capture({ "git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD" }, root)
                    target = resolved ~= "" and resolved or target
                end
                return base, target
            end
        end
    end

    return require("gitsigns.config").config.base, nil
end

--- `resolve_base` for the current worktree, warning when nothing at all resolves -- the
--- interactive keys need that: pressed expecting a diff, silence there reads as "nothing
--- changed" rather than "no base could be found".
local function pr_base()
    local root = worktree_root()
    local base = resolve_base(root)
    if not base then
        warn("no base is set -- run `:PrDiff <pr>` or pick one with `:PrList` first")
    end
    return base
end

--- The base made visible without running anything -- a loaded PR already has
--- `render_pr_tag`; this covers the ordinary case, no PR and no review session, where the
--- base is whatever `resolve_base` would answer right now. Distinguishes "resolved" from
--- "nothing resolves" rather than looking like no tag at all, which would read as "the
--- diff means nothing" when it actually means "no base is set".
render_diff_tag = function()
    local root = worktree_root()
    if not root then
        render_pr_tag(nil)
        return
    end
    local skim = skim_state(root)
    if skim and skim.pr then
        render_pr_tag(skim)
        return
    end
    statusline_base = statusline_base or vim.o.statusline
    local base, label = resolve_base(root)
    if not base then
        vim.opt.statusline = "%#PrTagWarn# no base %* " .. statusline_base
        return
    end
    vim.opt.statusline = string.format("%%#PrTag# vs %s@%s %%* ", (label or "base"):gsub("^origin/", ""), base:sub(1, 7))
        .. statusline_base
end

--- Every changed file with its status, side by side -- the same panel a session gets
--- from <Leader>rD. `<Leader>hd` is one file against the base, this is all of them.
---
--- With a PR loaded this is a commit range, so it renders as its author committed it:
--- the working tree there carries review markers, which are edits to the very files the
--- PR changed and would otherwise appear as the reader's own findings inside the diff
--- they are reading. No path expression can separate them -- a marker is a line in a
--- tracked file, not a file of its own.
---
--- With nothing loaded the question is "what have I changed", and an answer that stops
--- at the last commit is wrong by however much is still in the working tree. So the base
--- alone, which is diffview's way of saying "up to and including what is on disk".
function PR.panel()
    -- Toggling, matching <Leader>rD: the key that opened the panel closes it, so there
    -- is a way out without knowing diffview's own bindings.
    if next(require("diffview.lib").views) then
        vim.cmd("DiffviewClose")
        return
    end
    local base = pr_base()
    if not base then
        return
    end
    local root = worktree_root()
    if root and state.current_pr(root) then
        vim.cmd(("DiffviewOpen %s..HEAD"):format(base))
        return
    end
    vim.cmd(("DiffviewOpen %s"):format(base))
end

--- The changed files as a fuzzy finder, which is the way into one without knowing its
--- path -- the panel names the files but reaching one still means reading the list.
--- Lands in an ordinary editable buffer, so this is the key that ends a diff and starts
--- annotating. ctrl-d drops from the file list into that file's hunks.
function PR.files()
    local base = pr_base()
    if base then
        fzf.git_diff({
            ref1 = base,
            ref = "HEAD",
            cwd = worktree_root(),
            -- `git_diff` binds ctrl-q to its own git-commits picker, which shadows the
            -- fzf-level `select-all+accept` this config binds in every other picker -- so
            -- the key that means "send all of this to the quickfix list" everywhere else
            -- silently meant something unrelated here. Disabled rather than rebound, which
            -- lets the global binding through and keeps one meaning for the key. (fzf-lua's
            -- own quickfix actions sit on alt-q, unreachable on a Nordic Mac layout.)
            actions = { ["ctrl-q"] = false },
        })
    end
end

-- Another worktree ---------------------------------------------------------
--
-- The surfaces above answer for the worktree the working directory names, so reaching
-- another one's change is moving there and asking again -- not a second set of keys that
-- take a path. An agent, or a second `me wt`, works in a checkout that is a directory
-- away, and the whole cost of reading it should be picking it from a list.

--- Move to another worktree, picked by branch.
---
--- `:lcd` rather than `:cd`, because this is usually a visit: a window-local move leaves
--- every other split pointed at what it was already reading. The surfaces over the
--- change follow the working directory once it names a different worktree, so what to
--- press next is the same key as here -- there is no second diff key that takes a path.
---
--- The path travels in a hidden first field: the action needs the real one, and what is
--- worth reading is not.
function PR.worktrees()
    local root = worktree_root()
    if not root then
        return warn("not inside a git worktree")
    end
    local trees = list_worktrees(root)
    if #trees == 0 then
        return warn("no worktrees found")
    end
    local main = main_root(root)
    -- Branch first, because an agent's worktree is named for the branch it was cut for
    -- and the directory says nothing the branch does not. The path that follows is
    -- relative to the main checkout, which is the only part of it that differs between
    -- rows -- shown in full, every row opens with the same long prefix and the part being
    -- read is pushed off the end.
    local function label(tree)
        local shown = tree.path
        if main and shown == main then
            shown = vim.fs.basename(main)
        elseif main and shown:sub(1, #main + 1) == main .. "/" then
            shown = shown:sub(#main + 2)
        else
            -- A sibling clone rather than a linked worktree: nothing to make it relative
            -- to, so only the home directory is worth collapsing.
            shown = vim.fn.fnamemodify(shown, ":~")
        end
        return string.format("%-34s %s", tree.branch or ("detached @" .. tree.head:sub(1, 7)), shown)
    end

    local rows = vim.tbl_map(function(t)
        return string.format("%s\t%s", t.path, label(t))
    end, trees)
    fzf.fzf_exec(rows, {
        prompt = "worktree> ",
        preview = "git -C {1} log --color --oneline -20",
        fzf_opts = {
            ["--no-multi"] = true,
            ["--delimiter"] = "\t",
            ["--with-nth"] = "2..",
        },
        actions = {
            ["default"] = function(selected)
                local path = selected and selected[1] and selected[1]:match("^([^\t]+)")
                if not path then
                    return
                end
                if vim.fn.isdirectory(path) == 0 then
                    return warn(("%s no longer exists -- `git worktree prune`?"):format(path))
                end
                vim.cmd(("lcd %s"):format(vim.fn.fnameescape(path)))
                render_diff_tag()
                local base, label = resolve_base(path)
                if not base then
                    return warn(("moved to %s -- no base resolves there"):format(path))
                end
                vim.notify(("%s vs %s@%s"):format(path, (label or "base"):gsub("^origin/", ""), base:sub(1, 7)))
            end,
        },
    })
end

-- The PR list -------------------------------------------------------------
--
-- Organisation-wide rather than per repository, because that is the question being
-- asked: not "what is open here" but "what is there to review", which in a browser costs
-- a navigation per repository. The repository is a column, so narrowing to one is a few
-- keystrokes of the same fuzzy filter that finds everything else.
--
-- Three searches rather than one, because the fields that would answer this in one --
-- review decision, requested reviewers -- are not available on a search result, and
-- asking per PR would be a request each across hundreds. Search qualifiers answer it in
-- bulk instead: one list, and two sets to mark it up with. Run concurrently, since they
-- are independent and each is a round trip.
--
-- GitHub's search endpoint allows 30 requests a minute, an order of magnitude tighter
-- than the 5000/hour the rest of gh spends against. One listing costs three requests per
-- page of results, so roughly five listings a minute is the ceiling -- ample for reading
-- but the reason this is not refreshed on a timer or bound to a frequently-pressed key.
--
-- Two known gaps, both GitHub's rather than fixable here:
--   * `review-requested:@me` does not include PRs where a *team* you are in was asked --
--     that is `team-review-requested:<org/team>`, which needs a team slug this cannot
--     guess. A team-only request is therefore an unmarked row, not a missing one.
--   * `search(type: ISSUE)`, which `gh search prs` rides on, is being split into separate
--     issue and PR search. Expect this to need revisiting.

-- Not the whole org's backlog when the org has more than this: capped so one listing stays
-- three requests a page rather than ten, and the cap is reported when it bites rather than
-- quietly truncating into something that looks complete.
local LISTING_LIMIT = 200

local PR_ANSI = {
    requested = "\27[33m",
    repo = "\27[36m",
    number = "\27[90m",
    approved = "\27[32m",
    draft = "\27[90m",
    dim = "\27[90m",
    off = "\27[0m",
}

--- Which organisation the list covers. Derived from the repository you are standing in,
--- so nothing is hardcoded, with two overrides ahead of that: `REVIEW_PR_ORG` for pointing
--- a review pass somewhere else entirely, and `GH_REPO` -- gh's own
--- `[HOST/]OWNER/REPO` override -- because a shell that has already redirected every gh
--- call should not have this one search disagreeing with the rest.
local function owner_of(root)
    if vim.env.REVIEW_PR_ORG and vim.env.REVIEW_PR_ORG ~= "" then
        return vim.env.REVIEW_PR_ORG
    end
    if vim.env.GH_REPO and vim.env.GH_REPO ~= "" then
        local parts = vim.split(vim.env.GH_REPO, "/", { trimempty = true })
        if #parts >= 2 then
            return parts[#parts - 1]
        end
    end
    local raw, code = capture({ "gh", "repo", "view", "--json", "owner" }, root)
    if code ~= 0 then
        return nil
    end
    local ok, decoded = pcall(vim.json.decode, raw)
    return ok and decoded.owner and decoded.owner.login or nil
end

--- Numbers keyed `<repo>#<number>`, since a PR number is only unique within a repository
--- and this list spans many.
local function key_of(repo, number)
    return repo .. "#" .. number
end

local function search(args)
    return vim.system(vim.list_extend({ "gh", "search", "prs" }, args), { text = true })
end

-- Cached to disk, because the listing is a thing you reopen constantly -- to pick the next
-- PR, to check what is left -- and three search requests per open is a real cost against a
-- 30-a-minute budget.
--
-- A whole-listing cache with a short life, rather than the tempting "keep PRs that have not
-- moved in days and only re-fetch recent ones": an incrementally merged list has to
-- reconcile *disappearances* too, and a PR that merged while its row was cached would sit in
-- the list forever looking open. Re-fetching everything cannot drift, and the saving is the
-- same one -- the cost is per open, not per row.
--
-- The age is always in the title, so a stale answer is never a silent one.
local CACHE_SECONDS = tonumber(vim.env.REVIEW_PR_CACHE_SECONDS or "") or 900

local function cache_path(owner)
    return ("%s/pr-list-%s.json"):format(vim.fn.stdpath("cache"), owner:gsub("[^%w._-]", "_"))
end

-- The descriptions, one markdown file per PR, written from the listing that already
-- contains them. The preview is then a local render of a local file: stepping through the
-- list with <C-n>/<C-p> costs nothing, where a `gh pr view` per row would have spent a
-- request on every keypress and made moving through the list the expensive part.
local BODY_DIR = vim.fn.stdpath("cache") .. "/pr-bodies"

--- Repository names carry `-` and `.`, so the number is separated by a run that cannot
--- appear in either half.
body_path = function(repo, number)
    return ("%s/%s__%s.md"):format(BODY_DIR, repo:gsub("[^%w._-]", "_"), number)
end

--- The description as the preview will render it: what the list cannot show -- author,
--- age, a link -- above the body itself.
write_body = function(pr)
    local when = (pr.updatedAt or ""):match("^(%d+-%d+-%d+)") or "?"
    local head = {
        "# " .. (pr.title or "(no title)"),
        "",
        ("`%s#%s` · **%s** · updated %s%s"):format(
            pr.repository.name,
            pr.number,
            pr.author and pr.author.login or "?",
            when,
            pr.isDraft and " · draft" or ""
        ),
        "",
        pr.url or "",
        "",
        "---",
        "",
    }
    local body = pr.body
    if not body or vim.trim(body) == "" then
        body = "*No description.*"
    end
    vim.fn.mkdir(BODY_DIR, "p")
    local file = io.open(body_path(pr.repository.name, pr.number), "w")
    if not file then
        return
    end
    file:write(table.concat(head, "\n") .. body:gsub("\r\n", "\n"))
    file:close()
end

local function read_cache(owner, now)
    local file = io.open(cache_path(owner), "r")
    if not file then
        return nil
    end
    local raw = file:read("*a")
    file:close()
    local ok, cached = pcall(vim.json.decode, raw)
    if not ok or type(cached) ~= "table" or type(cached.prs) ~= "table" or not cached.at then
        return nil
    end
    local age = now - cached.at
    if age < 0 or age > CACHE_SECONDS then
        return nil
    end
    return cached, age
end

local function write_cache(owner, payload)
    local file = io.open(cache_path(owner), "w")
    if not file then
        return
    end
    file:write(vim.json.encode(payload))
    file:close()
end

--- Everything the listing needs, from the cache when it is young enough.
---
--- `now` is passed in rather than read here so one open stamps a single time, and `force`
--- is the picker's reload.
local function fetch_listing(owner, now, force)
    if not force then
        local cached, age = read_cache(owner, now)
        if cached then
            return cached.prs, cached.requested or {}, cached.approved or {}, age
        end
    end

    -- Most recently touched first. Worth stating rather than defaulting: gh sorts by
    -- `best-match`, which for a query with no search terms is an order with no meaning to
    -- read into -- and one that shuffles between calls, so the same list would come back
    -- differently arranged.
    local common = {
        "--owner",
        owner,
        "--state",
        "open",
        "--limit",
        tostring(LISTING_LIMIT),
        "--sort",
        "updated",
        "--order",
        "desc",
    }
    -- `body` comes down with the listing, which is what lets the description be previewed
    -- without a request per row. It is the one expensive field here, and the reason this is
    -- cached at all.
    local all = search(
        vim.list_extend(vim.deepcopy(common), { "--json", "number,title,repository,author,isDraft,body,updatedAt,url" })
    )
    local requested =
        search(vim.list_extend(vim.deepcopy(common), { "--review-requested", "@me", "--json", "number,repository" }))
    local approved =
        search(vim.list_extend(vim.deepcopy(common), { "--review", "approved", "--json", "number,repository" }))

    local all_result = all:wait()
    if all_result.code ~= 0 then
        warn("gh search prs failed -- " .. vim.trim(all_result.stderr or ""))
        return nil
    end
    local ok, prs = pcall(vim.json.decode, all_result.stdout)
    if not ok or type(prs) ~= "table" then
        warn("could not parse the PR search result")
        return nil
    end

    --- A failed markup search costs a flag, not the list, so these are read defensively:
    --- an unmarked row is still a row you can open.
    local function set_of(handle)
        local result, marked = handle:wait(), {}
        if result.code ~= 0 then
            return marked
        end
        local decoded_ok, decoded = pcall(vim.json.decode, result.stdout)
        if not decoded_ok or type(decoded) ~= "table" then
            return marked
        end
        for _, pr in ipairs(decoded) do
            marked[key_of(pr.repository.name, pr.number)] = true
        end
        return marked
    end
    local is_requested, is_approved = set_of(requested), set_of(approved)
    write_cache(owner, { at = now, prs = prs, requested = is_requested, approved = is_approved })
    return prs, is_requested, is_approved, 0
end

local function pr_rows(root, now, force)
    local owner = owner_of(root)
    if not owner then
        warn("could not tell which GitHub organisation this repository belongs to")
        return nil
    end
    local prs, is_requested, is_approved, age = fetch_listing(owner, now, force)
    if not prs then
        return nil
    end

    -- Requested first, then most recently updated. The list is long enough that ordering is
    -- the only thing keeping what you owe someone from being buried.
    --
    -- The original position is the tiebreaker because `table.sort` is not stable: without
    -- one, everything inside each of the two groups is free to come back in any order, and
    -- the recency the search was asked for would be discarded here.
    local position = {}
    for index, pr in ipairs(prs) do
        position[pr] = index
    end
    table.sort(prs, function(left, right)
        local left_owed = is_requested[key_of(left.repository.name, left.number)] and 1 or 0
        local right_owed = is_requested[key_of(right.repository.name, right.number)] and 1 or 0
        if left_owed ~= right_owed then
            return left_owed > right_owed
        end
        return position[left] < position[right]
    end)

    local repo_width = 0
    for _, pr in ipairs(prs) do
        repo_width = math.max(repo_width, #pr.repository.name)
    end
    repo_width = math.min(repo_width, 22)

    -- Half the width, less what the columns around it spend.
    local budget = math.max(30, math.floor(vim.o.columns * 0.5) - repo_width - 24)

    -- Each row carries its repository and number in two leading tab-delimited fields that
    -- fzf is told to hide (`--with-nth=3..`). fzf hands back the *original* line, so the
    -- action reads the identity straight off the selection.
    --
    -- The alternative -- a table keyed by the display string -- is what this did first, and
    -- it silently did nothing on enter: the rows carry colour, fzf returns them with the
    -- escapes stripped, and the stripped string is not the key that was stored. Hidden
    -- fields cannot drift that way, and they double as the preview's arguments.
    vim.fn.mkdir(BODY_DIR, "p")
    local rows = {}
    for _, pr in ipairs(prs) do
        write_body(pr)
        local key = key_of(pr.repository.name, pr.number)
        local title = pr.title
        if vim.fn.strdisplaywidth(title) > budget then
            title = vim.fn.strcharpart(title, 0, budget - 1) .. "…"
        end
        local flags = {}
        if is_approved[key] then
            table.insert(flags, PR_ANSI.approved .. "approved" .. PR_ANSI.off)
        end
        if pr.isDraft then
            table.insert(flags, PR_ANSI.draft .. "draft" .. PR_ANSI.off)
        end
        local row = table.concat({
            pr.repository.name,
            "\t",
            tostring(pr.number),
            "\t",
            is_requested[key] and (PR_ANSI.requested .. "▸" .. PR_ANSI.off) or " ",
            " ",
            PR_ANSI.repo,
            pr.repository.name .. string.rep(" ", math.max(1, repo_width - #pr.repository.name)),
            PR_ANSI.off,
            " ",
            PR_ANSI.number,
            string.format("#%-6s", pr.number),
            PR_ANSI.off,
            " ",
            title,
            string.rep(" ", math.max(1, budget - vim.fn.strdisplaywidth(title) + 2)),
            PR_ANSI.dim,
            pr.author and pr.author.login or "",
            PR_ANSI.off,
            #flags > 0 and ("  " .. table.concat(flags, " ")) or "",
        })
        table.insert(rows, row)
    end
    return rows, owner, age
end

--- The repository and number a selected row stands for.
local function row_identity(row)
    local repo, number = row:match("^([^\t]+)\t(%d+)\t")
    return repo, tonumber(number)
end

--- Load a PR here if this repository can hold it, or hand it to the surface that can.
---
--- A worktree belongs to one repository and its toolchain comes from that repository's
--- direnv environment, so a PR elsewhere cannot be read in this editor -- it needs the
--- skim surface of its own repository. `review skim` retargets the editor already open
--- there when there is one, so this does not pile up windows.
local function open_pr(repo, number, escalate)
    local root = worktree_root()
    local here = main_root(root)
    if not here then
        return warn("not inside a git worktree")
    end
    local same_repo = vim.fs.basename(here) == repo

    if escalate then
        local clone = same_repo and here or (vim.fs.dirname(here) .. "/" .. repo)
        if vim.fn.isdirectory(clone) == 0 then
            return warn(("no local clone of %s at %s"):format(repo, clone))
        end
        -- Detached, and through an interactive fish so the function and direnv are both
        -- there: it opens its own surface and must outlive this editor.
        vim.system({ "fish", "-i", "-c", "review " .. number }, { cwd = clone })
        vim.notify(("PR #%s in %s: opening a full review session"):format(number, repo))
        return
    end

    if same_repo and skim_state(root) then
        PR.load(tostring(number))
        -- The files are the point of picking a PR, so go straight there.
        if require("gitsigns.config").config.base then
            PR.files()
        end
        return
    end

    if same_repo then
        -- Not the skim surface: loading here would check out a branch over whatever this
        -- worktree is doing, which is not what picking from a list should mean.
        return warn(
            ("#%s is in this repository, but this is not the skim surface -- run `review skim %s`, or `:PrDiff %s` to load it here"):format(
                number,
                number,
                number
            )
        )
    end

    local clone = vim.fs.dirname(here) .. "/" .. repo
    if vim.fn.isdirectory(clone) == 0 then
        return warn(("no local clone of %s at %s"):format(repo, clone))
    end
    vim.system({ "fish", "-i", "-c", ("review skim %s"):format(number) }, { cwd = clone })
    vim.notify(("PR #%s in %s: opening that repository's skim surface"):format(number, repo))
end

--- How old the listing is, in the shortest form that is still honest.
local function freshness(age)
    if age < 60 then
        return "just fetched"
    end
    return ("%dm old"):format(math.floor(age / 60))
end

function PR.list(force)
    local root = worktree_root()
    if not root then
        return warn("not inside a git worktree")
    end
    -- Only announced when it will actually cost a round trip, so a cached open is silent.
    if force or not read_cache(owner_of(root) or "", os.time()) then
        vim.notify("PR: searching…")
    end
    local now = os.time()
    local rows, owner, age = pr_rows(root, now, force)
    if not rows then
        return
    end
    if #rows == 0 then
        return vim.notify(("PR: no open pull requests in %s"):format(owner))
    end
    -- Hitting the limit exactly is indistinguishable from an org that has precisely that
    -- many open, so this says "first N" rather than claiming a total it cannot know.
    local capped = #rows >= LISTING_LIMIT
    fzf.fzf_exec(rows, {
        prompt = "prs> ",
        winopts = {
            title = (" %s · %s%d open · %s · ▸ requested · ctrl-r session · ctrl-l reload "):format(
                owner,
                capped and "first " or "",
                #rows,
                freshness(age)
            ),
            preview = { layout = "flex" },
        },
        -- The description beside the list, rendered rather than raw: choosing what to read
        -- is mostly reading what the author says it is.
        --
        -- Rendered from a file written out of the listing, so walking the list with <C-n>
        -- costs nothing. A `gh pr view` per row would have spent a request on every keypress
        -- and made moving through the list the expensive part of using it.
        preview = ("glow -s dark -w ${FZF_PREVIEW_COLUMNS:-80} %s/{1}__{2}.md 2>/dev/null || echo '(no description — ctrl-l reloads)'"):format(
            BODY_DIR
        ),
        fzf_opts = {
            ["--ansi"] = true,
            ["--no-multi"] = true,
            -- Two hidden leading fields carry the identity; the eye sees from the third on.
            ["--delimiter"] = "\t",
            ["--with-nth"] = "3..",
        },
        actions = {
            ["default"] = function(selected)
                local repo, number = row_identity(selected and selected[1] or "")
                if repo and number then
                    open_pr(repo, number, false)
                end
            end,
            -- Reload, for when you know something landed since the cache was written.
            ["ctrl-l"] = function()
                vim.schedule(function()
                    PR.list(true)
                end)
            end,
            -- The escalation the surface exists to make cheap: skimming is where you find
            -- out a PR deserves the long form, so firing off a session belongs here.
            ["ctrl-r"] = function(selected)
                local repo, number = row_identity(selected and selected[1] or "")
                if repo and number then
                    open_pr(repo, number, true)
                end
            end,
        },
    })
end

-- Reading the description ------------------------------------------------
--
-- Wrapped in a block so its helpers cost no top-level local: see `state` above for why
-- this file counts them.
do
    --- Whether the cached description can still be trusted, against two independent gates.
    ---
    --- A head commit newer than the file is the real signal: an author who pushes has
    --- almost always rewritten the body in the same breath, and the check is local, since
    --- the head is fetched in every surface that can name a PR.
    ---
    --- It cannot stand alone. A description edited without a push -- a checklist ticked, a
    --- review answered in the body -- bumps no commit, so that gate alone would call the
    --- cache current for as long as the editor stayed open. The age gate bounds that.
    ---
    --- `updatedAt` is the true answer and is deliberately not used: reading it costs the
    --- very request being decided about.
    local MAX_BODY_AGE = 60 * 60

    local function body_is_current(path, root)
        local stat = vim.uv.fs_stat(path)
        if not stat then
            return false
        end
        local cached_at = stat.mtime.sec
        if os.time() - cached_at > MAX_BODY_AGE then
            return false
        end
        -- Bound to one name first: `capture` also returns the exit code, and passed
        -- straight through it would arrive as `tonumber`'s base.
        local committed = capture({ "git", "log", "-1", "--format=%ct", "HEAD" }, root)
        local committed_at = tonumber(committed)
        return not (committed_at and committed_at > cached_at)
    end

    --- Re-read a PR's description from GitHub and cache it. Returns true on success.
    local function fetch_body(repo, number, root)
        -- No `--repo`: gh resolves it from `root`, and that is always the right answer.
        -- All three surfaces record a PR belonging to the worktree recording it -- a PR in
        -- another repository is handed to that clone's own surface rather than read here.
        -- The recorded name is for keying the cache, which wants the bare one anyway.
        local raw, code, stderr = capture({
            "gh",
            "pr",
            "view",
            tostring(number),
            "--json",
            "title,body,url,author,updatedAt,isDraft",
        }, root)
        if code ~= 0 then
            warn(("gh could not read the description of #%s -- %s"):format(number, stderr))
            return false
        end
        local ok, pr = pcall(vim.json.decode, raw)
        if not ok then
            warn(("could not parse the description of #%s"):format(number))
            return false
        end
        -- `--repo` takes an owner-qualified name while the cache is keyed on the bare one,
        -- so the response's own repository name is what the file is written under.
        pr.repository = pr.repository or { name = repo }
        pr.number = number
        write_body(pr)
        return true
    end

    --- The description of the PR this worktree is reading, in a scratch buffer.
    ---
    --- A scratch buffer rather than the cache file itself: `gf`, folds and yanking all
    --- work either way, but an accidental write cannot corrupt the cache and the buffer
    --- list shows which PR this is instead of a mangled cache path.
    function PR.body(force)
        local root = worktree_root()
        if not root then
            return warn("not inside a git worktree")
        end
        local current = state.current_pr(root)
        if not current then
            return warn("no PR is loaded here -- `:PrDiff <pr>` or pick one with `:PrList` first")
        end

        local path = body_path(current.repo, current.number)
        if force or not body_is_current(path, root) then
            vim.notify(("PR: reading the description of #%s"):format(current.number))
            -- A failed fetch with nothing cached opens nothing: an empty buffer is
            -- indistinguishable from a PR whose description is genuinely empty, and the
            -- cache's own "no description" sentinel would state that as fact.
            if not fetch_body(current.repo, current.number, root) and vim.uv.fs_stat(path) == nil then
                return
            end
        end

        local file = io.open(path, "r")
        if not file then
            return warn(("no description cached for #%s"):format(current.number))
        end
        local lines = vim.split(file:read("*a"), "\n", { plain = true })
        file:close()

        local bufnr = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.api.nvim_buf_set_name(bufnr, ("pr://%s#%s"):format(current.repo, current.number))
        vim.bo[bufnr].filetype = "markdown"
        vim.bo[bufnr].buftype = "nofile"
        vim.bo[bufnr].bufhidden = "wipe"
        vim.bo[bufnr].modifiable = false
        vim.api.nvim_win_set_buf(0, bufnr)
    end
end

-- Bindings ----------------------------------------------------------------

vim.keymap.set("n", "<Leader>hl", function()
    PR.list(false)
end, { desc = "Pull requests across the org" })
vim.keymap.set("n", "<Leader>hD", PR.panel, { desc = "Every changed file against the base, side by side" })
vim.keymap.set("n", "<Leader>hf", PR.files, { desc = "Fuzzy find the changed files" })
vim.keymap.set("n", "<Leader>hb", function()
    PR.body(false)
end, { desc = "Read the loaded PR's description" })
-- Not fzf-lua's own `git_worktrees`, whose rows are absolute paths its action re-parses
-- for the path -- so the repeated prefix cannot be trimmed from the display without
-- breaking the move. Its add action is the stronger reason: it places a worktree beside
-- the repository rather than inside it and links no dependency tree, which is not how
-- worktrees are made here.
vim.keymap.set("n", "<Leader>hw", PR.worktrees, { desc = "Move to another worktree" })

-- `:PrList!` skips the cache, for the same reason ctrl-l exists inside the picker.
vim.api.nvim_create_user_command("PrList", function(opts)
    PR.list(opts.bang)
end, { bang = true, desc = "Open pull requests across the organisation (! re-fetches)" })
vim.api.nvim_create_user_command("PrDiff", function(opts)
    if opts.args ~= "" then
        return PR.load(opts.args)
    end
    vim.ui.input({ prompt = "PR number or URL: " }, function(value)
        if value and vim.trim(value) ~= "" then
            PR.load(value)
        end
    end)
end, {
    nargs = "?",
    desc = "Sign a PR's changes in the files (number, URL, or 'off')",
})

-- `:PrBody!` forces a re-read, for when the freshness gates were wrong -- the same role
-- `!` plays for `:PrList`.
vim.api.nvim_create_user_command("PrBody", function(opts)
    PR.body(opts.bang)
end, { bang = true, desc = "Read the loaded PR's description (! re-reads it)" })

--- Refs to complete `:DiffBase` against -- branches, remote branches and tags, the same
--- three namespaces `git checkout` completes, so nothing here needs guessing at the
--- shape of a name he would actually type.
local function ref_candidates(root)
    local raw = capture(
        { "git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes", "refs/tags" },
        root
    )
    return vim.split(raw, "\n", { trimempty = true })
end

vim.api.nvim_create_user_command("DiffBase", function(opts)
    local root = worktree_root()
    if not root then
        return warn("not inside a git worktree")
    end
    if opts.args:match("^%s*off%s*$") then
        reset_diff_base()
        render_diff_tag()
        vim.notify("PR: base back to the index")
        return
    end
    -- No argument means the base already on display: the statusline resolves one whether
    -- or not anything was ever named, and the sign column showing something else is the
    -- tag reporting a comparison that is not being made.
    --
    -- Cleared before resolving, because `resolve_base` answers with a named base first
    -- and would otherwise hand back whatever this is meant to replace.
    if opts.args == "" then
        reset_diff_base()
        local resolved, resolved_label = resolve_base(root)
        if not resolved then
            render_diff_tag()
            return warn("no base resolves here -- name a ref, or load a PR")
        end
        require("gitsigns").change_base(resolved, true)
        vim.env.REVIEW_BASE = resolved
        vim.env.REVIEW_BASE_DIR = root
        vim.env.REVIEW_BASE_LABEL = resolved_label
        render_diff_tag()
        vim.notify(
            ("PR: base set to %s (%s)"):format((resolved_label or "the merge base"):gsub("^origin/", ""), resolved:sub(1, 7))
        )
        return
    end
    local sha, code, stderr = capture({ "git", "rev-parse", "--verify", opts.args .. "^{commit}" }, root)
    if code ~= 0 or sha == "" then
        return warn(("%q does not resolve to a commit -- %s"):format(opts.args, stderr))
    end
    require("gitsigns").change_base(sha, true)
    vim.env.REVIEW_BASE = sha
    vim.env.REVIEW_BASE_DIR = root
    vim.env.REVIEW_BASE_LABEL = opts.args
    render_diff_tag()
    vim.notify(("PR: base set to %s (%s)"):format(opts.args, sha:sub(1, 7)))
end, {
    nargs = "?",
    complete = function(arglead)
        local root = worktree_root()
        if not root then
            return {}
        end
        local refs = ref_candidates(root)
        table.insert(refs, 1, "off")
        if arglead == "" then
            return refs
        end
        return vim.tbl_filter(function(ref)
            return ref:lower():find(arglead:lower(), 1, true) ~= nil
        end, refs)
    end,
    desc = "Sign the files against <ref>, or against the resolved base with no argument ('off' for the index)",
})

-- Restore the position on the skim surface: the detached checkout survives closing the
-- editor but the sign comparison does not, so without this the files look unchanged. Also
-- where the fallback tag first renders -- ask 3 (what am I diffing against) has to be
-- answered before any key is pressed, not after.
vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        vim.schedule(function()
            local root = worktree_root()
            local state = skim_state(root)
            if state and state.pr and state.base then
                require("gitsigns").change_base(state.base, true)
                vim.env.REVIEW_BASE = state.base
                vim.env.REVIEW_BASE_DIR = root
            end
            render_diff_tag()
        end)
    end,
})

-- The base can change without any of the keys above being pressed -- a branch switch in
-- a terminal outside nvim, most often -- and refocusing this window is the same signal
-- review.lua's own session tag already refreshes on.
vim.api.nvim_create_autocmd("FocusGained", {
    callback = render_diff_tag,
})
