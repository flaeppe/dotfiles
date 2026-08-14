local bufopts = { noremap = true }
--- Quicklist mappings
vim.keymap.set("n", "<Leader>q", "<Cmd>copen<CR>", bufopts)
vim.keymap.set("n", "<Leader>Q", "<Cmd>cclose<CR>", bufopts)
-- A count crosses several entries in one press, which is what a long list needs
-- once the statusline says how far along it is. Running off either end wraps
-- instead of erroring, so the walk never has to watch for the boundary.
vim.keymap.set("n", "<Leader>qj", function()
    if not pcall(vim.cmd, vim.v.count1 .. "cnext") then
        pcall(vim.cmd.cfirst)
    end
end, bufopts)
vim.keymap.set("n", "<Leader>qk", function()
    if not pcall(vim.cmd, vim.v.count1 .. "cprevious") then
        pcall(vim.cmd.clast)
    end
end, bufopts)

--- Format buffer
vim.keymap.set("n", "<Leader>ll", function()
    vim.lsp.buf.format({ async = true })
end, bufopts)
--- LSP (check :h lsp-defaults for default lsp bindings)
-- Reachable stand-in for CTRL-]. On a Swedish Mac layout ] is Option+9, so
-- CTRL-] would be Ctrl+Option+9, which macOS does not emit. Both go through
-- 'tagfunc' (vim.lsp.tagfunc), so this asks the language server first and
-- falls back to the tag file when no server is attached -- unlike grd below,
-- which is LSP-only. g CTRL-] rather than CTRL-] so an ambiguous name offers a
-- list instead of guessing the first match.
vim.keymap.set("n", "gd", "g<C-]>", { desc = "Definition (LSP via tagfunc, ctags fallback)" })
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
-- Inlay hints resolve inferred types in place, which is the fastest way to
-- check what a chain of generics or an untyped return actually produced. Left
-- off by default because they shift text horizontally as you read.
vim.keymap.set("n", "<Leader>ti", function()
    vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), { bufnr = 0 })
end, bufopts)
-- Move to next item
vim.keymap.set("n", "¨d", function() vim.diagnostic.jump({ count = 1, float = true }) end, bufopts)
-- Move to previous item
vim.keymap.set("n", "åd", function() vim.diagnostic.jump({ count = -1, float = true }) end, bufopts)
