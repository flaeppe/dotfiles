-- Symbol outline for the current file. LSP is tried first because it is the
-- only backend that resolves types; treesitter covers filetypes with no server
-- attached, which in this config includes .sql outside a configured Postgres
-- project and any .graphql outside a graphql-config root.
require("aerial").setup({
    backends = { "lsp", "treesitter", "markdown", "man" },
    layout = { min_width = 34 },
    -- Follow the cursor, so the outline doubles as a "where am I" indicator in
    -- long files.
    highlight_on_jump = 300,
    show_guides = true,
})
vim.keymap.set("n", "<Leader>o", "<Cmd>AerialToggle!<CR>", { desc = "Toggle symbol outline" })
vim.keymap.set("n", "<Leader>O", "<Cmd>AerialNavToggle<CR>", { desc = "Toggle floating symbol nav" })
