-- Whole-change browsing: a file panel listing every changed path with its status, and a
-- side-by-side view per file. The "files changed" surface -- a review needs to answer
-- "how big is this, and what else moved" before any individual finding means anything.
--
-- Opens in its own tab, so `q` closes the whole thing rather than leaving a half-torn
-- diff behind.

local actions = require("diffview.actions")

require("diffview").setup({
    enhanced_diff_hl = true,
    hooks = {
        -- A revision's buffer is named `diffview://<git dir>/<rev>/<path>`. In a linked
        -- worktree the git dir is `<main>/.git/worktrees/<name>`, a prefix long enough
        -- that the tabline and statusline cut the part worth reading (`src/...`) away.
        -- The buffer takes the place its file has in the checkout instead, suffixed with
        -- the revision so it never collides with the working-tree buffer of that path.
        diff_buf_read = function(bufnr)
            local view = require("diffview.lib").get_current_view()
            if not view then
                return
            end
            local RevType = require("diffview.vcs.rev").RevType
            for _, file in ipairs(view.cur_layout:files()) do
                if file.bufnr == bufnr then
                    local revision
                    if file.rev.type == RevType.COMMIT then
                        revision = file.rev:abbrev(7)
                    elseif file.rev.type == RevType.STAGE then
                        revision = "index"
                    else
                        -- The working tree is an ordinary file buffer, named by its path.
                        return
                    end
                    -- Relative to the working directory, which is how `:ls` lists a file
                    -- buffer; a name set absolute is listed absolute.
                    local name = vim.fn.fnamemodify(("%s/%s@%s"):format(file.adapter.ctx.toplevel, file.path, revision), ":.")
                    local previous_name = vim.api.nvim_buf_get_name(bufnr)
                    -- Fails when a buffer already holds the name; the long name still works.
                    if not pcall(vim.api.nvim_buf_set_name, bufnr, name) then
                        return
                    end
                    -- Renaming leaves an empty buffer behind under the old name, which is
                    -- the name diffview looks a revision's buffer up by when the diff is
                    -- opened again -- it would find the empty one instead of reading the file.
                    for _, other in ipairs(vim.api.nvim_list_bufs()) do
                        if other ~= bufnr and vim.api.nvim_buf_get_name(other) == previous_name then
                            vim.api.nvim_buf_delete(other, { force = true })
                        end
                    end
                    return
                end
            end
        end,
    },
    keymaps = {
        -- `gf` is the way out of read-only browsing and into the file itself, which
        -- is where a suggestion actually gets edited. Bound explicitly rather than
        -- left to defaults because it is the point of opening the diff at all.
        --
        -- The two <Leader> defaults are dropped: a diff is a place you read code in,
        -- so the buffer list and the symbol picker have to keep meaning what they
        -- mean everywhere else. Nothing replaces them -- <Tab> already walks the
        -- files, <C-w>h reaches the panel, and hiding the panel is not worth a key.
        view = {
            { "n", "q", "<Cmd>DiffviewClose<CR>", { desc = "Close the diff" } },
            { "n", "gf", actions.goto_file_edit, { desc = "Open this file for editing" } },
            { "n", "<leader>b", false },
            { "n", "<leader>e", false },
        },
        file_panel = {
            { "n", "q", "<Cmd>DiffviewClose<CR>", { desc = "Close the diff" } },
            { "n", "gf", actions.goto_file_edit, { desc = "Open this file for editing" } },
            { "n", "<leader>b", false },
            { "n", "<leader>e", false },
        },
        file_history_panel = {
            { "n", "q", "<Cmd>DiffviewClose<CR>", { desc = "Close the diff" } },
            { "n", "<leader>b", false },
            { "n", "<leader>e", false },
        },
    },
})
