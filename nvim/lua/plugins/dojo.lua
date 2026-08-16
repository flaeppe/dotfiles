-- The Dojo: what is bound, what you actually reach for, and what you are
-- currently drilling. `<Leader>?` or `:Dojo`.
--
-- More than a cheatsheet, which is why it is not called one. Three things share
-- one surface because they answer one question -- "what should I be reaching
-- for?" -- from three directions: the vocabulary you have, the vocabulary you
-- use, and the habit you are working on right now.
--
-- Deliberately not generated from the keymap table. Everything bound would be a
-- reference manual; this is the shorter list worth reaching for, described by
-- *when* to reach for it, since that is what you would search on. Prune as
-- freely as you add -- an entry nobody searches for costs space.
--
-- A key already in the fingers is not searched for either. It earns a row only
-- when there is a sibling to choose between, or when it is rare enough that you
-- would have to look it up. Reflexes belong in the log, not here: the review
-- counts every key pressed, listed or not, so dropping a row loses no evidence.
--
-- `added` is the date an entry appeared here, rendered as an age. A binding four
-- months old that you still never press is a different problem from one added
-- last week. Set it when you add a row; never backdate it to flatter yourself.
-- `run = false` marks an entry that documents behaviour rather than a mapping
-- this can fire (a key meaningful only inside a picker, a builtin with no
-- mapping behind it, a motion needing a target).

local fzf = require("fzf-lua")

local ENTRIES = {
    -- Find
    { group = "find", keys = "<Leader>f", desc = "Grep text across the project (ripgrep)", added = "2025-08-09" },
    {
        group = "find",
        keys = "<Leader>F",
        desc = "Every fzf-lua picker, when you forget which exists",
        added = "2025-08-09",
    },
    {
        group = "find",
        keys = "<Leader>b",
        desc = "What is already open (and the way back after a stray :q)",
        added = "2026-07-27",
    },

    -- Plans: the header is the index, so the vocabulary earns a row of its own
    {
        group = "plan",
        keys = "<Leader>p",
        desc = "What was the plan? Every plan, narrowed by what its header claims (ctrl-g: grep just those)",
        added = "2026-08-16",
    },
    {
        group = "plan",
        keys = "<Leader>P",
        desc = "Search the text of every plan, when there is no facet to narrow by first",
        added = "2026-08-16",
    },
    {
        group = "plan",
        keys = "@svc =status #dir",
        desc = "In that list: @service, =status, #folder, .category, ?review, ?stale -- and 'word to match fuzzily",
        added = "2026-08-16",
        run = false,
    },

    -- Symbols: the two indexes answer different questions
    {
        group = "symbol",
        keys = "<C-e>",
        desc = "Project symbols -- ctags: instant, complete, every language at once",
        added = "2019-08-02",
    },
    {
        group = "symbol",
        keys = "<Leader>e",
        desc = "Project symbols -- LSP: type-accurate, empty until the server is warm",
        added = "2026-07-25",
    },
    { group = "symbol", keys = "<Leader>d", desc = "Symbols in this file", added = "2026-07-25" },
    { group = "symbol", keys = "<Leader>o", desc = "Outline sidebar, stays open while you read", added = "2026-07-25" },

    -- Jump
    {
        group = "jump",
        keys = "gd",
        desc = "Definition -- LSP first, ctags fallback, reachable on a Nordic layout",
        added = "2026-07-25",
    },
    {
        group = "jump",
        keys = "grs",
        desc = "Definition in source, past a generated .d.ts (TypeScript)",
        added = "2026-07-25",
    },
    { group = "jump", keys = "grt", desc = "Type definition", added = "2025-08-06" },
    { group = "jump", keys = "gri", desc = "Implementation", added = "2025-08-06" },

    -- References and call hierarchy
    {
        group = "reference",
        keys = "<Leader>cr",
        desc = "References in a picker, to narrow before committing to walking them",
        added = "2026-07-25",
    },
    { group = "reference", keys = "<Leader>ci", desc = "Incoming calls: who reaches this", added = "2026-07-25" },
    { group = "reference", keys = "<Leader>co", desc = "Outgoing calls: what this reaches", added = "2026-07-25" },

    -- Quickfix: the loop that turns a search into a work list
    { group = "quickfix", keys = "<Leader>q", desc = "Open the quickfix list", added = "2025-08-09" },
    {
        group = "quickfix",
        keys = "<Leader>qj",
        desc = "Next entry, or a count of them (wraps to first)",
        added = "2025-08-09",
    },
    {
        group = "quickfix",
        keys = "<Leader>qk",
        desc = "Previous entry, or a count of them (wraps to last)",
        added = "2025-08-09",
    },
    {
        group = "quickfix",
        keys = "<Leader>qf",
        desc = "Fuzzy-match an entry, for lists too long to step through",
        added = "2026-08-14",
    },
    {
        group = "quickfix",
        keys = "ctrl-q",
        desc = "Inside any picker: send ALL matches to the quickfix list",
        added = "2025-08-09",
        run = false,
    },

    -- Structural motion, treesitter-driven, works inside embedded gql/sql too
    { group = "motion", keys = "¨f  åf", desc = "Next / previous function", added = "2026-07-25", run = false },
    { group = "motion", keys = "¨t  åt", desc = "Next / previous class or type", added = "2026-07-25", run = false },
    { group = "motion", keys = "af  if", desc = "Select function, outer / inner", added = "2026-07-25", run = false },
    {
        group = "motion",
        keys = "at  it",
        desc = "Select class or type, outer / inner",
        added = "2026-07-25",
        run = false,
    },
    { group = "motion", keys = "aa  ia", desc = "Select parameter, outer / inner", added = "2026-07-25", run = false },

    -- Change
    {
        group = "edit",
        keys = "grn",
        desc = "Rename symbol across the project, writing every file it touched",
        added = "2025-08-06",
    },
    { group = "edit", keys = "gra", desc = "Code action", added = "2025-08-06" },

    -- Diagnostics
    { group = "diagnostic", keys = "¨d", desc = "Next diagnostic", added = "2025-02-23" },
    { group = "diagnostic", keys = "åd", desc = "Previous diagnostic", added = "2025-02-23" },
    { group = "diagnostic", keys = "<Leader>ts", desc = "Show diagnostics", added = "2022-12-29" },
    { group = "diagnostic", keys = "<Leader>th", desc = "Hide diagnostics", added = "2022-12-29" },

    -- Toggles
    {
        group = "toggle",
        keys = "<Leader>ti",
        desc = "Inlay hints: resolve inferred types in place",
        added = "2026-07-25",
    },

    -- Review: annotating a PR in place, in the code, rather than in a web diff
    {
        group = "review",
        keys = "<Leader>ro",
        desc = "Start a review: walk it in the order given",
        added = "2026-07-25",
    },
    {
        group = "review",
        keys = "<Leader>rc",
        desc = "Something is wrong here, decide later how to raise it",
        added = "2026-07-25",
    },
    {
        group = "review",
        keys = "<Leader>rf",
        desc = "Wrong and you know the fix -- ship it as code",
        added = "2026-07-25",
    },
    { group = "review", keys = "<Leader>ra", desc = "Not wrong, but ask the author about it", added = "2026-07-25" },
    {
        group = "review",
        keys = "<Leader>rn",
        desc = "A thought for yourself; never leaves the worktree",
        added = "2026-07-25",
    },
    {
        group = "review",
        keys = "<Leader>rr",
        desc = "Same problem as one you already wrote -- link, don't repeat",
        added = "2026-07-25",
    },
    {
        group = "review",
        keys = "V then <Leader>rc",
        desc = "Finding about a whole block: select it first, and the comment covers the range",
        added = "2026-08-12",
        run = false,
    },
    { group = "review", keys = "<Leader>rl", desc = "What have I found so far?", added = "2026-07-25" },
    {
        group = "review",
        keys = "<Leader>rY",
        desc = "Findings to the clipboard as markdown, to paste into the PR yourself",
        added = "2026-08-10",
    },
    {
        group = "review",
        keys = ":GithubApprove",
        desc = "Approve, with every marker posted as an inline comment (:wq posts, :q! abandons)",
        added = "2026-08-11",
    },
    {
        group = "review",
        keys = ":GithubComment",
        desc = "Same, without a verdict -- and :GithubRequestChanges for the other one",
        added = "2026-08-11",
    },
    {
        group = "review",
        keys = "<Leader>rq",
        desc = "Walk the actual changed code, hunk by hunk, in files you can edit",
        added = "2026-07-25",
    },
    { group = "review", keys = "<Leader>rd", desc = "Retract the marker here", added = "2026-07-25" },
    { group = "review", keys = "<Leader>rw", desc = "Done reviewing -- harvest the findings", added = "2026-07-25" },
    { group = "review", keys = "<Leader>rt", desc = "Where does the review stand?", added = "2026-07-26" },
    {
        group = "review",
        keys = "<Leader>rj",
        desc = "Open this same file and line in the other worktree's editor",
        added = "2026-07-26",
    },
    {
        group = "review",
        keys = "<Leader>rb",
        desc = "Showing this round or the whole suggestion? Switch (stack only)",
        added = "2026-07-26",
    },
    {
        group = "review",
        keys = ":ReviewAccept",
        desc = "Take this change into the review (! takes all of it; no id = pick)",
        added = "2026-07-26",
    },

    {
        group = "review",
        keys = "<Leader>rD",
        desc = "How big is this change? Every changed file, side by side (<Leader>rb sets scope)",
        added = "2026-07-26",
    },
    {
        group = "review",
        keys = "<Leader>rp",
        desc = "Lost? Where the session stands and what is next",
        added = "2026-07-26",
    },

    -- Hunks: the accept/discard pair a review runs on
    { group = "hunk", keys = "<Leader>hs", desc = "Accept this hunk (again to un-accept)", added = "2026-07-26" },
    { group = "hunk", keys = "<Leader>hu", desc = "Throw this hunk away", added = "2026-07-26" },
    { group = "hunk", keys = "<Leader>hp", desc = "What exactly changed here?", added = "2026-07-26" },
    { group = "hunk", keys = "<Leader>hd", desc = "This whole file against the base", added = "2026-07-26" },
    {
        group = "hunk",
        keys = "<Leader>hl",
        desc = "What is there to review? Every open PR in the org, description beside it (ctrl-r: session, ctrl-l: reload)",
        added = "2026-08-10",
    },
    {
        group = "hunk",
        keys = ":PrDiff",
        desc = "Read one named PR as hunks -- paste a number or URL ('off' to stop)",
        added = "2026-08-10",
    },
    {
        group = "hunk",
        keys = "<Leader>hD",
        desc = "How big is this? Every changed file against the base (the :PrDiff overview)",
        added = "2026-08-10",
    },
    {
        group = "hunk",
        keys = "<Leader>hf",
        desc = "Jump straight to a changed file, fuzzily -- no path to remember (ctrl-q: all of them)",
        added = "2026-08-10",
    },
    { group = "hunk", keys = "¨h  åh", desc = "Next / previous changed hunk", added = "2026-07-26", run = false },
    {
        group = "review",
        keys = "¨r  år",
        desc = "Next / previous marker in this file",
        added = "2026-07-25",
        run = false,
    },

    -- Tree
    { group = "tree", keys = "<Leader>nf", desc = "Reveal the current file in the tree", added = "2019-08-02" },

    -- Markdown
    { group = "markdown", keys = "<Leader>mp", desc = "Toggle live markdown preview", added = "2026-07-20" },

    -- The training loop itself
    { group = "dojo", keys = ":KeylogStatus", desc = "Where the keystroke log is, and how big", added = "2026-07-25" },
    {
        group = "dojo",
        keys = ":KeylogToggle",
        desc = "Pause keystroke logging (pairing, screen sharing)",
        added = "2026-07-25",
    },
}

-- Written by the periodic keystroke review, not by this file and not by the
-- logger. Reading a small summary rather than aggregating the raw log keeps this
-- instant no matter how large the log has grown. Absent until the first review
-- runs, which is fine -- the usage column is then simply blank.
local REVIEW = vim.fn.stdpath("state") .. "/keylog/review.json"

local function read_review()
    local fd = io.open(REVIEW, "r")
    if not fd then
        return nil
    end
    local raw = fd:read("*a")
    fd:close()
    local ok, decoded = pcall(vim.json.decode, raw)
    return ok and decoded or nil
end

local function age(added)
    if not added then
        return "?"
    end
    local year, month, day = added:match("^(%d+)-(%d+)-(%d+)$")
    if not year then
        return "?"
    end
    local stamp = os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 })
    local days = math.floor(os.difftime(os.time(), stamp) / 86400)
    if days < 7 then
        return "new"
    elseif days < 60 then
        return string.format("%dw", math.floor(days / 7))
    elseif days < 730 then
        return string.format("%dmo", math.floor(days / 30))
    end
    return string.format("%dy", math.floor(days / 365))
end

local function render(review, unused_only)
    local counts = review and review.counts or {}
    local drills = review and review.drills or {}
    local width = 0
    for _, entry in ipairs(ENTRIES) do
        width = math.max(width, #entry.keys)
    end
    local lines, meta = {}, {}
    -- Drills first: this should open on the homework, not on an alphabet.
    for _, drill in ipairs(drills) do
        local line =
            string.format("%-10s  %-" .. width .. "s  %5s %4s  %s", "DRILL", drill.keys or "", "", "", drill.note or "")
        table.insert(lines, line)
        meta[line] = { keys = drill.keys, run = drill.keys ~= nil and drill.keys ~= "" }
    end
    for _, entry in ipairs(ENTRIES) do
        local used = counts[entry.keys]
        if not (unused_only and used and used > 0) then
            local usage = review and (used and used > 0 and string.format("%5d", used) or "    ·") or "     "
            local line = string.format(
                "%-10s  %-" .. width .. "s  %s %4s  %s",
                entry.group,
                entry.keys,
                usage,
                age(entry.added),
                entry.desc
            )
            table.insert(lines, line)
            meta[line] = { keys = entry.keys, run = entry.run ~= false }
        end
    end
    return lines, meta
end

local function open(unused_only)
    local review = read_review()
    local lines, meta = render(review, unused_only)
    fzf.fzf_exec(lines, {
        prompt = "dojo> ",
        winopts = {
            title = unused_only and " dojo -- never pressed " or (review and " dojo " or " dojo (no review yet) "),
            height = 0.8,
            width = 0.9,
        },
        actions = {
            -- Fire the mapping rather than only reading about it: searching for
            -- "who reaches this" and pressing enter should do the thing.
            ["default"] = function(selected)
                local entry = selected and meta[selected[1]]
                if not entry or not entry.run then
                    return
                end
                local keys = entry.keys:gsub("<Leader>", vim.g.mapleader or " ")
                -- A ":Command" entry needs the newline a keymap does not.
                if keys:match("^:%a") then
                    keys = keys .. "\r"
                end
                vim.schedule(function()
                    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "m", false)
                end)
            end,
            -- The most useful question to ask of a reference you wrote yourself:
            -- which of this have I never actually reached for?
            ["ctrl-u"] = function()
                vim.schedule(function()
                    open(not unused_only)
                end)
            end,
        },
    })
end

vim.keymap.set("n", "<Leader>?", function()
    open(false)
end, { desc = "Dojo (ctrl-u: only what I never press)" })

vim.api.nvim_create_user_command("Dojo", function()
    open(false)
end, { desc = "Keybindings, usage and current drills" })

-- Start page. Deferred rather than run straight from VimEnter because `-c`
-- commands execute after VimEnter: a session that opens a tree and splits (see
-- the kitty session for this repo) would otherwise get the Dojo on top of it.
-- By the time this runs the window count reveals whether anything else claimed
-- the startup.
vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        vim.schedule(function()
            local untouched = vim.fn.argc() == 0
                and #vim.api.nvim_list_wins() == 1
                and vim.api.nvim_buf_get_name(0) == ""
                and vim.api.nvim_buf_line_count(0) == 1
                and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == ""
            if untouched then
                open(false)
            end
        end)
    end,
})
