local fzf = require("fzf-lua")
-- Directories that stay excluded even when gitignore-respecting is toggled
-- off with alt-i (unlike .gitignore entries, these are never useful to browse).
local FILE_PICKER_DENYLIST = {
    ".git", ".jj", "node_modules", ".direnv", ".venv", "venv", ".pytest_cache", ".ruff_cache", "__pycache__",
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
vim.keymap.set("n", "F", function()
    fzf.builtin()
end, { desc = "View fzf-lua commands" })
vim.keymap.set("n", "<C-p>", function()
    fzf.files()
end, { silent = true, desc = "Search files with FZF" })
vim.keymap.set("n", "<C-e>", function()
    fzf.tags()
end, { desc = "Search ctags" })
vim.keymap.set("n", "<Leader>f", function()
    fzf.grep_project()
end, { remap = true, silent = true, desc = "Search text with ripgrep" })
