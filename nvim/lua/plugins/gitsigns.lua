-- Hunk signs, and the two actions a review needs: accept a change into the next
-- commit, or discard it.
--
-- The comparison base is what makes this a review tool rather than a change indicator,
-- and it is set per worktree during a review session -- see docs/pr-review.md. Staging
-- is the accept mechanism at line granularity, which is why the keys below are
-- range-aware and why staged changes need a sign of their own.

require("gitsigns").setup({
    -- An untracked file has nothing to compare against, so every line would sign as
    -- added -- which says less than the file's mere presence already does.
    attach_to_untracked = false,
    -- Staged changes get their own sign, which is the third state a review needs:
    -- unstaged is in flight, staged is accepted but not yet committed, no sign is
    -- settled. Only meaningful while the diff base is the index -- naming an
    -- explicit revision leaves one diff with nothing to distinguish.
    signs_staged_enable = true,
})

local gitsigns = require("gitsigns")

local function map(keys, fn, desc)
    vim.keymap.set({ "n", "v" }, keys, fn, { desc = desc })
end

-- Hunk motion. ]c/[c stay bound for muscle memory, but `]` is Option+9 on a Nordic Mac
-- layout, so ¨h/åh are bound too, as the dead-key pair that's actually reachable.
map("]c", function()
    gitsigns.nav_hunk("next")
end, "Next hunk")
map("[c", function()
    gitsigns.nav_hunk("prev")
end, "Previous hunk")
map("¨h", function()
    gitsigns.nav_hunk("next")
end, "Next hunk")
map("åh", function()
    gitsigns.nav_hunk("prev")
end, "Previous hunk")

-- Range-aware: in visual mode these act on the selected lines only, which is
-- what makes accepting a subset of scattered edits possible.
local function selected_range()
    local first, last = vim.fn.line("v"), vim.fn.line(".")
    if first > last then
        first, last = last, first
    end
    return { first, last }
end

-- stage_hunk toggles: called on an already-staged sign it unstages, which is why
-- there is no separate unstage key.
map("<Leader>hs", function()
    gitsigns.stage_hunk(vim.fn.mode():match("[vV]") and selected_range() or nil)
end, "Stage hunk, or unstage a staged one (or selection)")
map("<Leader>hu", function()
    gitsigns.reset_hunk(vim.fn.mode():match("[vV]") and selected_range() or nil)
end, "Discard hunk (or selection)")
map("<Leader>hp", gitsigns.preview_hunk, "Preview hunk")

-- Toggling, because diffthis opens a scratch window showing the base and there is
-- otherwise no obvious way back out of a diff you only wanted a glance at.
map("<Leader>hd", function()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)):match("^gitsigns:") then
            vim.api.nvim_win_close(win, true)
            vim.cmd("diffoff")
            return
        end
    end
    gitsigns.diffthis()
end, "Diff this file against the base, or close that diff")
