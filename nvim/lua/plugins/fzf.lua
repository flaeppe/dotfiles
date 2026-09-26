local fzf = require("fzf-lua")
-- Directories that stay excluded even when gitignore-respecting is toggled
-- off with alt-i (unlike .gitignore entries, these are never useful to browse).
local FILE_PICKER_DENYLIST = {
    -- .worktrees and .claude/worktrees hold checkouts of the same repo: every
    -- hit in them is a duplicate of one in the root project, on a different
    -- branch.
    ".git", ".jj", ".worktrees", ".claude/worktrees", "node_modules", ".direnv", ".venv", "venv", ".pytest_cache", ".ruff_cache", "__pycache__",
    "dist", "build", "out", "target", ".next",
}
fzf.setup({
    fzf_colors = true,
    winopts = {
        width = 0.9,
        height = 0.9,
    },
    files = {
        -- Show gitignored files by default (e.g. untracked local dirs), but
        -- keep the denylist hidden regardless. Only VCS-based ignore rules
        -- (.gitignore, .git/info/exclude) are skipped -- a project-local
        -- `.ignore` file (fd/rg's git-independent convention) is still
        -- honored, so that's the place for per-project picker excludes.
        -- alt-i toggles back to respecting .gitignore too, if wanted.
        no_ignore = true,
        toggle_ignore_flag = "--no-ignore-vcs",
        fd_opts = "--color=never --type f --type l "
            .. table.concat(vim.tbl_map(function(dir) return "--exclude " .. dir end, FILE_PICKER_DENYLIST), " "),
        rg_opts = "--color=never --files "
            .. table.concat(vim.tbl_map(function(dir) return "-g '!" .. dir .. "'" end, FILE_PICKER_DENYLIST), " "),
        -- Option/Alt keys inside nvim on macOS+kitty are reported as raw
        -- keyboard events rather than composed text, so alt-i (the default)
        -- breaks non-US keyboard layouts.
        actions = {
            ["ctrl-o"] = { fzf.actions.toggle_ignore },
        },
    },
    grep = {
        -- Persistent blacklist (nvim/grep-blacklist, gitignore syntax --
        -- add lockfiles etc. there), always applied regardless of the
        -- ignore-vcs toggle below, same as the files picker's denylist.
        rg_opts = "--glob '!.git/*' --ignore-file " .. vim.fn.stdpath("config") .. "/grep-blacklist"
            .. " --column --line-number --no-heading --color=always --smart-case --max-columns=4096 -e",
        hidden = true,
        -- Respect .gitignore by default; ctrl-o toggles it off to widen
        -- the results to gitignored matches too.
        toggle_ignore_flag = "--no-ignore-vcs",
        actions = {
            ["ctrl-o"] = { fzf.actions.toggle_ignore },
        },
    },
    keymap = {
        fzf = {
            -- Send results to quicklist
            ["ctrl-q"] = "select-all+accept",
        },
    },
})
fzf.register_ui_select()
-- Under the leader rather than bare `F`, which is the builtin backwards
-- character search on the current line -- a motion, and one that pairs with `f`.
vim.keymap.set("n", "<Leader>F", function()
    fzf.builtin()
end, { desc = "View fzf-lua commands" })
vim.keymap.set("n", "<C-p>", function()
    fzf.files()
end, { silent = true, desc = "Search files with FZF" })
-- What is already open, which is also how you find your way back after a stray :q
-- closed the window you were reading.
vim.keymap.set("n", "<Leader>b", function()
    fzf.buffers()
end, { desc = "Open buffers" })
-- Reach one quickfix entry by typing part of its text, for lists long enough
-- that stepping to the entry costs more than naming it.
vim.keymap.set("n", "<Leader>qf", function()
    fzf.quickfix()
end, { desc = "Quickfix entries" })
-- Symbol navigation.
--
-- ctags and the LSP have complementary blind spots, so both stay bound rather
-- than one replacing the other. ctags indexes every language in the repo at
-- once, needs no running server, and survives syntax errors -- but it tags
-- every `const x = () => {}` as a plain constant, never descends into object
-- literals (so resolver maps and route tables yield one tag for the whole
-- object), and has no GraphQL parser at all. The LSP is type-accurate and
-- knows dependencies, but only answers for servers attached to the current
-- buffer, so in a mixed Go/TS repo it sees one language at a time.
--
-- They are bound to separate keys rather than one key choosing between them.
-- Capability is the wrong signal to choose on: graphql-lsp advertises
-- workspaceSymbolProvider, so "some attached client answers workspace/symbol"
-- is true in any repo with a graphql-config long before tsserver has loaded a
-- project graph, and the picker then reports the GraphQL server's empty answer
-- while never consulting the tag file. The two also differ in kind -- the tag
-- index is complete the moment it exists, a server answers only once warm --
-- so a single key makes an empty result impossible to interpret.
vim.keymap.set("n", "<C-e>", function()
    fzf.tags()
end, { desc = "Project symbols (ctags, every language at once)" })
vim.keymap.set("n", "<Leader>e", function()
    fzf.lsp_live_workspace_symbols()
end, { desc = "Project symbols (LSP, type-accurate)" })
local function lsp_supports(method)
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
        if client:supports_method(method) then
            return true
        end
    end
    return false
end
-- The outline sidebar stays on screen beside the picker, as a map of the whole
-- file to read names from while typing the query. The picker is sized to the
-- side of the sidebar with more room, so the float never covers it.
vim.keymap.set("n", "<Leader>d", function()
    local aerial = require("aerial")
    local outline_was_open = aerial.is_open()
    aerial.open({ focus = false })
    local outline_win
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "aerial" then
            outline_win = win
        end
    end
    local winopts = {}
    if outline_win then
        local outline_col = vim.api.nvim_win_get_position(outline_win)[2]
        local outline_end = outline_col + vim.api.nvim_win_get_width(outline_win) + 1
        local room_left = outline_col - 1
        local room_right = vim.o.columns - outline_end
        if room_left >= room_right then
            winopts = { col = 0, width = room_left }
        else
            winopts = { col = outline_end, width = room_right }
        end
        -- The backdrop dims the whole editor, the sidebar included.
        winopts.backdrop = false
        winopts.on_close = function()
            if not outline_was_open and vim.api.nvim_win_is_valid(outline_win) then
                vim.api.nvim_win_close(outline_win, false)
            end
        end
    end
    if lsp_supports("textDocument/documentSymbol") then
        return fzf.lsp_document_symbols({ winopts = winopts })
    end
    fzf.btags({ winopts = winopts })
end, { desc = "Document symbols, with the outline sidebar beside them" })
-- Call hierarchy has no ctags equivalent: tags record where a name is defined,
-- never who reaches it.
vim.keymap.set("n", "<Leader>ci", function()
    fzf.lsp_incoming_calls()
end, { desc = "Incoming calls" })
vim.keymap.set("n", "<Leader>co", function()
    fzf.lsp_outgoing_calls()
end, { desc = "Outgoing calls" })
vim.keymap.set("n", "<Leader>cr", function()
    fzf.lsp_references({ includeDeclaration = false })
end, { desc = "References" })
vim.keymap.set("n", "<Leader>f", function()
    fzf.grep_project()
end, { remap = true, silent = true, desc = "Search text with ripgrep" })
