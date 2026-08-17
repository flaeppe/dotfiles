-- Every planning document under ~/.plan, filterable by what its header claims it is.
--
-- A plan is filed under the repository it belongs to -- ~/.plan/<repo>/, as a flat
-- <description>.md or a <project>/NNN-*.md series -- except the cross-repo ones, which
-- are filed under _cross/ and belong to several. The filing directory therefore cannot
-- answer "what is still open in payout" -- only the header's `services:` list can, and
-- that list has the same shape for both kinds of plan.
-- So each row carries its header as sigil-prefixed tokens and fzf's own query algebra does
-- the filtering: `@payout =draft`, `@api !=complete`, `#_cross ?`.
--
--   @service   every repo in `services:`, so a _cross plan touching payout answers @payout
--   #dir       where it is filed, repository-qualified: #_cross, #api/de-signing-provider
--   =status    the six words the planning skill allows, `=?` for a header claiming none
--   .category  code | docs | ticket | record
--   ?review    the header carries a `review:` flag in place of a `verified:` stamp
--   ?stale     verified, but longer ago than the threshold `plan-status --stale` uses
--
-- The tokens go in the visible half of the row rather than a hidden leading field, because
-- fzf matches against what `--with-nth` leaves displayed: a field hidden behind
-- `--with-nth=2..` cannot be searched for at all. Only the path is hidden -- nothing is
-- ever typed at it, it is there for the preview and for opening.
--
--   <Leader>p    the list; ctrl-g greps whatever the query has left on screen
--   <Leader>P    grep every plan, for when there is no facet to narrow by first

local fzf = require("fzf-lua")

local PLAN_ROOT = vim.fn.expand("~/.plan")
-- Sweep machinery and frontmatter backups: files *about* the plan tree rather than part
-- of it, and numerous enough to bury the plans if they were listed alongside them.
local EXCLUDED_DIR = "_private"
-- The same threshold `plan-status --stale` defaults to, so ?stale means one thing.
local STALE_DAYS = 30

-- How wide the preview has to be, and no wider.
--
-- Measured against the tree rather than picked: glow re-wraps a plan to whatever width it
-- is handed, so what the files themselves are wrapped at decides nothing. Rendered at 96
-- columns every plan here comes out with no line cut; at 88, all but a handful, and those
-- by four columns. Anything past that is blank band -- and the columns it hands back are
-- what let a row show its title and its facets at the same time.
local PREVIEW_COLUMNS = 96
-- What `winopts.width` in the fzf-lua setup leaves the picker of the terminal.
local WINDOW_FRACTION = 0.9

local function preview_width()
    return math.max(48, math.min(PREVIEW_COLUMNS, math.floor(vim.o.columns * WINDOW_FRACTION * 0.5)))
end

--- The columns the list gets once the window and the preview have taken theirs.
local function list_width()
    return math.floor(vim.o.columns * WINDOW_FRACTION) - preview_width()
end

local ANSI = {
    directory = "\27[36m",
    service = "\27[35m",
    flag = "\27[33m",
    dim = "\27[90m",
    off = "\27[0m",
}

-- Substring matching rather than fzf's default fuzzy, which scatters a query's characters
-- across the whole row: fuzzy `@api` also matches a row reading `@anyfin-platform .ticket`,
-- and fuzzy `=?` matches every `=draft` that also carries a `?review`, so the facet counts
-- come out wrong in the direction that is hardest to notice -- too many rows, all of them
-- plausible. Fuzzy is still a keystroke away: under `--exact`, fzf reads a leading `'` as
-- "match this term fuzzily", which is what a half-remembered title wants anyway.
local MATCHING = { ["--exact"] = true }

local STATUSES = { "draft", "in progress", "complete", "superseded", "deferred", "abandoned" }

local STATUS_ANSI = {
    ["draft"] = "\27[33m",
    ["in-progress"] = "\27[32m",
    ["complete"] = "\27[90m",
    ["deferred"] = "\27[34m",
    ["superseded"] = "\27[90m",
    ["abandoned"] = "\27[31m",
    ["?"] = "\27[31m",
}

local function warn(message)
    vim.notify("Plan: " .. message, vim.log.levels.ERROR)
end

--- The `key: value` header of a plan, and the first heading under it.
---
--- Reads the head of the file only: a header is a handful of lines and the title is the
--- line after it, so listing the tree costs one short read per plan rather than a parse.
local function header(path)
    local lines = vim.fn.readfile(path, "", 40)
    if lines[1] ~= "---" then
        return nil, nil
    end
    local meta, title, closed = {}, nil, false
    for index = 2, #lines do
        if closed then
            title = lines[index]:match("^#%s+(.+)$")
            if title then
                break
            end
        elseif lines[index] == "---" then
            closed = true
        else
            local key, value = lines[index]:match("^(%w[%w_]*):%s*(.*)$")
            if key then
                meta[key] = value
            end
        end
    end
    return closed and meta or nil, title
end

--- The canonical status a header claims, as a token.
---
--- `?` for one that claims none: the skill allows six words and puts any nuance in
--- `status_note`, so an unrecognised status is a header to go fix, and `=?` is how the
--- list is asked which those are.
local function status_token(raw)
    local lowered = (raw or ""):lower()
    for _, canonical in ipairs(STATUSES) do
        if lowered:sub(1, #canonical) == canonical then
            return (canonical:gsub(" ", "-"))
        end
    end
    return "?"
end

--- Every repository a plan touches, `@<ref>` suffixes dropped -- a PR number only resolves
--- next to a repository, and it is the repository that is worth filtering on.
local function service_tokens(raw)
    local tokens = {}
    for name in (raw or ""):gmatch("[^%[%],]+") do
        name = vim.trim(name):gsub("@.*$", "")
        if name ~= "" then
            table.insert(tokens, ANSI.service .. "@" .. name .. ANSI.off)
        end
    end
    return tokens
end

--- Days since a `verified:` stamp, or nil when the header carries none.
local function age_days(stamp)
    local year, month, day = (stamp or ""):match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    if not year then
        return nil
    end
    local stamped = os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = 12,
    })
    return math.floor(os.difftime(os.time(), stamped) / 86400)
end

--- A filename with the parts that have their own column taken off: the extension, and the
--- sequence number.
local function stem_of(name)
    return (name:gsub("%.md$", ""):gsub("^%d+%-", ""))
end

--- What a plan calls itself, falling back to its filename when it has no heading.
local function title_of(heading, name)
    if heading then
        return heading
    end
    return (stem_of(name):gsub("%-", " "))
end

--- One row per plan: the path in a hidden leading field, then everything worth typing at.
local function rows()
    -- One glob per repository rather than one over the tree: descending into the excluded
    -- directory and discarding what comes back costs more than every header read combined.
    local paths = {}
    for name, kind in vim.fs.dir(PLAN_ROOT) do
        if kind == "directory" and name ~= EXCLUDED_DIR then
            vim.list_extend(paths, vim.fn.glob(PLAN_ROOT .. "/" .. name .. "/**/*.md", true, true))
        end
    end

    -- Where a title stops and its facets start. A cap, not a column: padding every title
    -- out to the same width lines the facets up, and costs the alignment far more than it
    -- is worth -- it spends the gap after a short title on nothing, which pushes that row's
    -- facets off the edge for no reason. Ragged, four rows in ten fit the list entirely
    -- against one in a hundred padded, and three quarters of all facets are on screen
    -- against half. 72 is past where these titles stop getting longer, so the cap still
    -- leaves nearly nine in ten of them whole.
    local budget = math.max(30, math.min(72, math.floor((list_width() - 19) * 0.6)))

    local built = {}
    for _, path in ipairs(paths) do
        local relative = path:sub(#PLAN_ROOT + 2)
        local meta, heading = header(path)
        if meta then
            local name = vim.fs.basename(relative)
            local status = status_token(meta.status)
            local title = title_of(heading, name)
            if vim.fn.strdisplaywidth(title) > budget then
                title = vim.fn.strcharpart(title, 0, budget - 1) .. "…"
            end

            -- Ordered by what is worth the screen columns rather than by kind, since only
            -- the first few survive the edge: a flag is the reason to look at the row at
            -- all, the services are what the row is about, and the folder is both the
            -- longest token and the one the sort order has already grouped the row by.
            local facets = {}
            if meta.review then
                table.insert(facets, ANSI.flag .. "?review" .. ANSI.off)
            end
            local age = age_days(meta.verified)
            if age and age > STALE_DAYS then
                table.insert(facets, ANSI.flag .. ("?stale(%dd)"):format(age) .. ANSI.off)
            end
            vim.list_extend(facets, service_tokens(meta.services))
            table.insert(facets, ANSI.directory .. "#" .. vim.fs.dirname(relative) .. ANSI.off)
            table.insert(facets, ANSI.dim .. "." .. (meta.category or "?") .. ANSI.off)
            -- The filename last, because typing at it has to work: on half of these plans it
            -- carries a word the heading does not (`scope-and-sequence` over "Mark the
            -- payments file uploaded"), and the path itself is in the hidden field, where
            -- fzf will not match against it.
            table.insert(facets, ANSI.dim .. stem_of(name) .. ANSI.off)

            local row = table.concat({
                path,
                "\t",
                ANSI.dim,
                ("%-4s"):format(name:match("^(%d+)") or ""),
                ANSI.off,
                STATUS_ANSI[status] or "",
                ("%-13s"):format("=" .. status),
                ANSI.off,
                title,
                "  ",
                table.concat(facets, " "),
            })
            table.insert(built, row)
        end
    end
    -- Path order, which is repository, then project, then sequence number -- the order the
    -- skill says to read a series in.
    table.sort(built)
    return built
end

--- The files a set of rows stands for.
local function paths_of(selected)
    local paths = {}
    for _, row in ipairs(selected or {}) do
        local path = row:match("^([^\t]+)\t")
        if path then
            table.insert(paths, path)
        end
    end
    return paths
end

--- One plan opens; several become a quickfix list, which is what ctrl-q's select-all
--- means in every other picker here.
local function open(selected)
    local paths = paths_of(selected)
    if #paths == 0 then
        return
    end
    if #paths == 1 then
        return vim.cmd.edit(vim.fn.fnameescape(paths[1]))
    end
    vim.fn.setqflist({}, " ", {
        title = "plans",
        items = vim.tbl_map(function(path)
            return { filename = path, lnum = 1 }
        end, paths),
    })
    vim.cmd.copen()
end

--- Grep the plans a query has left on screen.
---
--- Which those are is settled by putting the same rows through `fzf --filter` under the
--- flags the picker ran with, so the grep is scoped to exactly what was visible. Deriving
--- the narrowing again here -- reading the tokens out of the query and matching them
--- against the headers -- would be a second implementation of fzf's matcher, and would
--- start disagreeing with the list the first time a query used anything but a plain term.
local function grep(narrowing)
    local all = rows()
    if #all == 0 then
        return warn("no plans under " .. PLAN_ROOT)
    end
    if narrowing and narrowing ~= "" then
        local argv = { "fzf", "--ansi", "--delimiter", "\t", "--with-nth", "2.." }
        for flag in pairs(MATCHING) do
            table.insert(argv, flag)
        end
        vim.list_extend(argv, { "--filter", narrowing })
        local result = vim.system(argv, { stdin = table.concat(all, "\n"), text = true }):wait()
        all = vim.split(result.stdout or "", "\n", { trimempty = true })
    end
    local paths = paths_of(all)
    if #paths == 0 then
        return warn(("nothing matches %q"):format(narrowing))
    end
    fzf.live_grep({
        prompt = "plan grep> ",
        -- Searched and reported relative to the plan tree, so a result reads as the plan it
        -- is rather than spending its first 24 columns on a prefix every row shares.
        cwd = PLAN_ROOT,
        search_paths = vim.tbl_map(function(path)
            return path:sub(#PLAN_ROOT + 2)
        end, paths),
        winopts = { title = (" %d plan%s "):format(#paths, #paths == 1 and "" or "s") },
    })
end

local function list()
    local all = rows()
    if #all == 0 then
        return warn("no plans under " .. PLAN_ROOT)
    end
    fzf.fzf_exec(all, {
        prompt = "plans> ",
        winopts = {
            title = (" %d plans · @service #dir =status .category ?review ?stale · 'fuzzy · ctrl-g grep these "):format(
                #all
            ),
            preview = { layout = "flex", horizontal = ("right:%d"):format(preview_width()) },
        },
        -- Rendered rather than raw: deciding which plan to open is mostly reading what
        -- each one says it is, and the header this list filters on is the top of the file.
        --
        -- The fallback matches the pane asked for just above, so that losing the variable
        -- costs a couple of columns rather than wrapping the text at an unrelated width and
        -- leaving the rest of the pane empty.
        preview = ("glow -s dark -w ${FZF_PREVIEW_COLUMNS:-%d} {1}"):format(preview_width()),
        fzf_opts = vim.tbl_extend("error", MATCHING, {
            ["--ansi"] = true,
            -- The path is field 1 and stays hidden; the eye and the query see from 2 on.
            ["--delimiter"] = "\t",
            ["--with-nth"] = "2..",
            -- Rows stay anchored at their left edge. Left to scroll, fzf chases a match
            -- that sits out past the edge -- and since the facets are the rightmost thing
            -- on the row, typing a facet is exactly the case that scrolls: every row slides
            -- until the sequence, status and title are gone and the list reads as a column
            -- of sentence fragments. The match highlight goes off-screen instead, which
            -- costs nothing, because the query is the thing you just typed.
            ["--no-hscroll"] = true,
        }),
        actions = {
            ["default"] = function(selected)
                open(selected)
            end,
            -- fzf-lua always passes `--print-query`, so the typed query comes back here.
            ["ctrl-g"] = function(_, opts)
                vim.schedule(function()
                    grep(opts.last_query)
                end)
            end,
        },
    })
end

vim.api.nvim_create_user_command("Plan", list, { desc = "Plans, filtered by header" })
vim.api.nvim_create_user_command("PlanGrep", function()
    grep(nil)
end, { desc = "Search the text of every plan" })

vim.keymap.set("n", "<Leader>p", list, { desc = "Plans, filtered by header" })
vim.keymap.set("n", "<Leader>P", function()
    grep(nil)
end, { desc = "Search the text of every plan" })
