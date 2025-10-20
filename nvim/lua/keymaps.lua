local bufopts = { noremap = true }
--- Quicklist mappings
vim.keymap.set("n", "<Leader>q", "<Cmd>copen<CR>", bufopts)
vim.keymap.set("n", "<Leader>Q", "<Cmd>cclose<CR>", bufopts)
vim.keymap.set("n", "<Leader>qj", "<Cmd>try | cnext | catch | cfirst | catch | endtry<CR>", bufopts)
vim.keymap.set("n", "<Leader>qk", "<Cmd>try | cprevious | catch | clast | catch | endtry<CR>", bufopts)

--- Format buffer
vim.keymap.set("n", "<Leader>ll", function()
    vim.lsp.buf.format({ async = true })
end, bufopts)
--- LSP (check :h lsp-defaults for default lsp bindings)
vim.keymap.set("n", "grd", vim.lsp.buf.definition, bufopts)
vim.keymap.set("n", "grD", vim.lsp.buf.declaration, bufopts)
vim.keymap.set("n", "grt", vim.lsp.buf.type_definition, bufopts)
-- Open diagnostic in a floating window
vim.keymap.set("n", "<Leader>le", function()
    vim.diagnostic.open_float(nil, { focus = false })
end, bufopts)
-- Show/hide diagnostic
vim.keymap.set("n", "<Leader>ts", vim.diagnostic.show, bufopts)
vim.keymap.set("n", "<Leader>th", vim.diagnostic.hide, bufopts)
-- Move to next item
vim.keymap.set("n", "¨d", function() vim.diagnostic.jump({ count = 1, float = true }) end, bufopts)
-- Move to previous item
vim.keymap.set("n", "åd", function() vim.diagnostic.jump({ count = -1, float = true }) end, bufopts)
