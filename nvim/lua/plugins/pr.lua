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
--
-- The two surfaces over the change work without a PR loaded at all: with no base named
-- they fall back to the merge base with the default branch, so `nvim` in an ordinary
-- checkout answers "what has this branch changed" with the same keys. See `pr_base`.
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

--- The git worktree holding the current buffer, which is not always the editor's cwd.
local function worktree_root()
    local dir = vim.fn.expand("%:p:h")
    if dir == "" or vim.fn.isdirectory(dir) == 0 then
        dir = vim.uv.cwd()
    end
    local root, code = capture({ "git", "rev-parse", "--show-toplevel" }, dir)
    return code == 0 and root or nil
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

local function skim_state(root)
    local file = io.open(skim_file(root), "r")
    if not file then
        return nil
    end
    local raw = file:read("*a")
    file:close()
    local ok, decoded = pcall(vim.json.decode, raw)
    return ok and decoded or nil
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

local statusline_base = nil

local function render_pr_tag(state)
    statusline_base = statusline_base or vim.o.statusline
    if not (state and state.pr) then
        vim.opt.statusline = statusline_base
        return
    end
    vim.opt.statusline = string.format("%%#PrTag# SKIM · #%s %%* ", state.pr) .. statusline_base
end

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
        require("gitsigns").reset_base(true)
        -- Cleared rather than left standing: with it set, the surfaces would keep
        -- answering with a PR the sign column has already stopped signing.
        vim.env.REVIEW_BASE = nil
        vim.env.REVIEW_BASE_DIR = nil
        local skim = skim_state(root)
        if skim then
            skim.pr = nil
            write_skim_state(root, skim)
            render_pr_tag(skim)
        end
        vim.notify("PR: base back to the index")
        return nil
    end

    local number = pr_number(input)
    if not number then
        return warn(("expected a PR number or a pull-request URL, got %q"):format(input))
    end

    local raw, code, stderr =
        capture({ "gh", "pr", "view", number, "--json", "title,headRefOid,baseRefName,headRefName" }, root)
    if code ~= 0 then
        return warn(("gh could not read PR #%s in %s -- %s"):format(number, root, stderr))
    end
    local ok, pr = pcall(vim.json.decode, raw)
    if not ok then
        return warn("could not parse the gh response")
    end

    local skim = skim_state(root)
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

        if skim then
            -- A ref outside refs/heads, so it never appears in a branch listing and never
            -- competes with the author's branch of the same name.
            local ref = "refs/skim/" .. number
            local _, fetch_code, fetch_error = capture(
                { "git", "fetch", "--quiet", "--force", "origin", ("pull/%s/head:%s"):format(number, ref) },
                root
            )
            if fetch_code ~= 0 then
                return warn(("could not fetch pull/%s/head -- %s"):format(number, fetch_error))
            end
            local _, checkout_code, checkout_error = capture({ "git", "checkout", "--detach", "--force", ref }, root)
            if checkout_code ~= 0 then
                return warn(("could not check out #%s -- %s"):format(number, checkout_error))
            end
        else
            local _, checkout_code, checkout_error = capture({ "gh", "pr", "checkout", number }, root)
            if checkout_code ~= 0 then
                return warn(("could not check out #%s -- %s"):format(number, checkout_error))
            end
        end
    end

    capture({ "git", "fetch", "--quiet", "origin", pr.baseRefName }, root)
    local target = "origin/" .. pr.baseRefName
    local base, base_code = capture({ "git", "merge-base", target, "HEAD" }, root)
    if base_code ~= 0 or base == "" then
        return warn(("no merge base between %s and the head of #%s"):format(target, number))
    end

    local changed = capture({ "git", "diff", "--name-only", base, "HEAD" }, root)
    local count = #vim.split(changed, "\n", { trimempty = true })

    if skim then
        wipe_file_buffers()
        skim.pr = tonumber(number)
        skim.title = pr.title
        skim.base = base
        write_skim_state(root, skim)
        render_pr_tag(skim)
    end

    -- All three, always together: the sign column and the surfaces over the change read
    -- different variables, and one of them left behind is a panel describing the PR that
    -- was loaded before this one. The worktree the base belongs to travels with it, so
    -- an editor started from here in another worktree does not inherit an answer about
    -- this one.
    require("gitsigns").change_base(base, true)
    vim.env.REVIEW_BASE = base
    vim.env.REVIEW_BASE_DIR = root
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
local function pr_base()
    local root = worktree_root()

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
            return vim.env.REVIEW_BASE
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
                return base
            end
        end
    end

    local loaded = require("gitsigns.config").config.base
    if loaded then
        return loaded
    end
    warn("no base is set -- run `:PrDiff <pr>` or pick one with `:PrList` first")
end

--- Every changed file with its status, side by side -- the same panel a session gets
--- from <Leader>rD. `<Leader>hd` is one file against the base, this is all of them.
---
--- A commit range, not the bare base, because the panel renders its own buffers: the PR
--- shows as its author committed it, with the markers the working tree carries left out.
function PR.panel()
    -- Toggling, matching <Leader>rD: the key that opened the panel closes it, so there
    -- is a way out without knowing diffview's own bindings.
    if next(require("diffview.lib").views) then
        vim.cmd("DiffviewClose")
        return
    end
    local base = pr_base()
    if base then
        vim.cmd(("DiffviewOpen %s..HEAD"):format(base))
    end
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
local function body_path(repo, number)
    return ("%s/%s__%s.md"):format(BODY_DIR, repo:gsub("[^%w._-]", "_"), number)
end

--- The description as the preview will render it: what the list cannot show -- author,
--- age, a link -- above the body itself.
local function write_body(pr)
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

-- Bindings ----------------------------------------------------------------

vim.keymap.set("n", "<Leader>hl", function()
    PR.list(false)
end, { desc = "Pull requests across the org" })
vim.keymap.set("n", "<Leader>hD", PR.panel, { desc = "Every changed file against the base, side by side" })
vim.keymap.set("n", "<Leader>hf", PR.files, { desc = "Fuzzy find the changed files" })

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

-- Restore the position on the skim surface: the detached checkout survives closing the
-- editor but the sign comparison does not, so without this the files look unchanged.
vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        vim.schedule(function()
            local root = worktree_root()
            local state = skim_state(root)
            if not (state and state.pr and state.base) then
                return
            end
            require("gitsigns").change_base(state.base, true)
            vim.env.REVIEW_BASE = state.base
            vim.env.REVIEW_BASE_DIR = root
            render_pr_tag(state)
        end)
    end,
})
