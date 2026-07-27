-- Whole-change browsing: a file panel listing every changed path with its status, and a
-- side-by-side view per file. The "files changed" surface -- a review needs to answer
-- "how big is this, and what else moved" before any individual finding means anything.
--
-- Opens in its own tab, so `q` closes the whole thing rather than leaving a half-torn
-- diff behind.

local actions = require("diffview.actions")

require("diffview").setup({
    enhanced_diff_hl = true,
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
