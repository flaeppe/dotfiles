-- Whitespace trimming function and autocommand
local trim_augroup = vim.api.nvim_create_augroup("TrimWhitespace", { clear = true })

-- Autocommand to remove whitespace before writing a buffer
vim.api.nvim_create_autocmd("BufWritePre", {
    group = trim_augroup,
    pattern = "",
    command = ":%s/\\s\\+$//e",
})

-- gopls and marksman (see lspconfig.lua) both list filetypes Neovim doesn't
-- detect on its own -- without these, the LSP simply never attaches for
-- these extensions.
vim.filetype.add({
    extension = {
        tmpl = "gotmpl",
        gotmpl = "gotmpl",
        mdx = "markdown.mdx",
    },
})
