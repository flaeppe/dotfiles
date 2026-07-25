-- Keystroke log, for reviewing editing habits after the fact.
--
-- Scope is deliberately narrow. Only normal, visual, select and
-- operator-pending keys are recorded: insert and replace mode is where
-- passwords, tokens and prose get typed, and it is also where the least
-- efficiency signal lives. Command lines are recorded as the leading command
-- token only (`s`, `e`, `vs`), never the arguments.
--
-- The log stays raw and unaggregated on purpose. A better question to ask of the
-- data can then be applied to history already collected, which would be
-- impossible if capture pre-summarised into counters.
--
-- One file per session per day, so a review can read a date range without
-- parsing months of history, and so pruning is a file deletion rather than a
-- rewrite. Per session and not merely per day because several nvim instances are
-- normally open at once, and one shared file breaks under that two ways:
-- interleaved appends splice two keystreams into a sequence nobody typed --
-- inventing adjacencies, which is precisely what a review reasons over -- and
-- concurrent writes tear records apart at the 4096-byte stdio buffer boundary.
-- Records are self-contained (`t` is absolute), so files merge on read.
--
-- `:KeylogToggle` stops recording for the session -- for pairing or screen
-- sharing. `:KeylogStatus` reports where the files are and how large they got.

local DIR = vim.fn.stdpath("state") .. "/keylog"
local RETENTION_DAYS = 60

-- Only these count as "editing". nvim_get_mode() returns operator-pending as
-- "no"/"nov"/"noV", visual as "v"/"V"/CTRL-V, select as "s"/"S"/CTRL-S.
local RECORDED_MODES = {
    n = true,
    no = true,
    nov = true,
    noV = true,
    ["no\22"] = true,
    v = true,
    V = true,
    ["\22"] = true,
    s = true,
    S = true,
    ["\19"] = true,
}

local enabled = true
local pending = {}
local filetype = ""
local last_path = nil
-- When the current batch opened, and where. A file's opening context has to
-- describe the first keystroke in it, not the flush that happened to write it.
local batch_start_ms = nil
local batch_cwd = nil

local PID = vim.fn.getpid()

-- hrtime() rather than now(): now() returns the event loop's cached timestamp,
-- which does not advance within a single loop iteration, and several keys can
-- land in one iteration. That would collapse exactly the gaps this exists to
-- measure -- a key every second while reading a file means something different
-- from eight of the same key in half a second.
local session_start_ns = vim.uv.hrtime()
local session_start_ms = os.time() * 1000

local function now_ms()
    return session_start_ms + math.floor((vim.uv.hrtime() - session_start_ns) / 1e6)
end

local function log_path()
    return string.format("%s/keys-%s-%d.jsonl", DIR, os.date("%Y-%m-%d"), PID)
end

-- Which project the keys belong to. A record carrying `cwd` is context rather
-- than a keystroke, and applies to every record after it until the next one.
local function context(cwd)
    return { cwd = cwd or vim.fn.getcwd(), nvim = tostring(vim.version()), pid = PID }
end

local function flush()
    if #pending == 0 then
        return
    end
    local lines = pending
    pending = {}
    vim.fn.mkdir(DIR, "p")
    local path = log_path()
    local fd = io.open(path, "a")
    if not fd then
        return
    end
    -- Opens every file this session writes with context, which also covers a
    -- session running past midnight into a second day's file.
    if path ~= last_path then
        last_path = path
        local ctx = context(batch_cwd)
        ctx.t = batch_start_ms
        table.insert(lines, 1, vim.json.encode(ctx))
    end
    fd:write(table.concat(lines, "\n") .. "\n")
    fd:close()
end

local function record(entry)
    entry.t = now_ms()
    if #pending == 0 then
        batch_start_ms = entry.t
        batch_cwd = vim.fn.getcwd()
    end
    table.insert(pending, vim.json.encode(entry))
    if #pending >= 200 then
        flush()
    end
end

local function prune()
    local cutoff = os.time() - RETENTION_DAYS * 86400
    local ok, iter = pcall(vim.fs.dir, DIR)
    if not ok then
        return
    end
    for name, kind in iter do
        local year, month, day = name:match("^keys%-(%d+)%-(%d+)%-(%d+)[%-.]")
        if kind == "file" and year and name:match("%.jsonl$") then
            local stamp = os.time({
                year = tonumber(year),
                month = tonumber(month),
                day = tonumber(day),
                hour = 12,
            })
            if stamp < cutoff then
                os.remove(DIR .. "/" .. name)
            end
        end
    end
end

vim.fn.mkdir(DIR, "p")
prune()

vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
    callback = function()
        filetype = vim.bo.filetype
    end,
})

-- :cd mid-session moves the keys to a different project, so context is recorded
-- inline as well as at the top of the file.
vim.api.nvim_create_autocmd("DirChanged", {
    callback = function()
        if enabled then
            record(context())
        end
    end,
})

vim.on_key(function(_, typed)
    if not enabled then
        return
    end
    -- on_key removes the callback on error, which would silently end logging
    -- for the session, so nothing in here is allowed to throw.
    pcall(function()
        -- `typed` is empty when the key came out of a mapping expansion rather
        -- than a finger, and counting those would inflate whatever the mapping
        -- happens to expand to.
        if typed == nil or typed == "" then
            return
        end
        local mode = vim.api.nvim_get_mode().mode
        if not RECORDED_MODES[mode] then
            return
        end
        record({ m = mode, k = vim.fn.keytrans(typed), ft = filetype })
    end)
end)

-- The command name is the useful part for habit review -- whether a substitute
-- was reached for where a picker would serve, how often a file is opened with
-- :e rather than the file picker. The arguments are where the secrets are, so
-- they are dropped.
vim.api.nvim_create_autocmd("CmdlineLeave", {
    callback = function()
        if not enabled or vim.fn.getcmdtype() ~= ":" then
            return
        end
        local line = vim.fn.getcmdline() or ""
        local name = line:match("^%s*[%%%d,.$'<>+-]*(%a+)") or line:match("^%s*(%p)")
        if name then
            record({ m = "c", cmd = name, ft = filetype })
        end
    end,
})

local timer = vim.uv.new_timer()
timer:start(60000, 60000, vim.schedule_wrap(flush))

vim.api.nvim_create_autocmd("VimLeavePre", { callback = flush })

vim.api.nvim_create_user_command("KeylogToggle", function()
    enabled = not enabled
    flush()
    vim.notify("keylog " .. (enabled and "recording" or "paused"))
end, { desc = "Pause or resume keystroke logging" })

vim.api.nvim_create_user_command("KeylogStatus", function()
    flush()
    local files, bytes = 0, 0
    local days = {}
    local ok, iter = pcall(vim.fs.dir, DIR)
    if ok then
        for name, kind in iter do
            local date = name:match("^keys%-(%d+%-%d+%-%d+)")
            if kind == "file" and date and name:match("%.jsonl$") then
                files = files + 1
                days[date] = true
                bytes = bytes + math.max(vim.fn.getfsize(DIR .. "/" .. name), 0)
            end
        end
    end
    vim.notify(
        string.format(
            "keylog %s\n%s\nthis session: %s\n%d file(s) across %d day(s), %.1f MiB total, keeping %d days",
            enabled and "recording" or "paused",
            DIR,
            vim.fs.basename(log_path()),
            files,
            vim.tbl_count(days),
            bytes / 1024 / 1024,
            RETENTION_DAYS
        )
    )
end, { desc = "Show keystroke logging status" })
