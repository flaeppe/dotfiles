--- Navigation
local kitty_nav = require('plugins/kitty_nav')
vim.keymap.set('n', '<C-h>', function() kitty_nav.navigate('h') end)
vim.keymap.set('n', '<C-j>', function() kitty_nav.navigate('j') end)
vim.keymap.set('n', '<C-k>', function() kitty_nav.navigate('k') end)
vim.keymap.set('n', '<C-l>', function() kitty_nav.navigate('l') end)
--- Quicklist mappings
vim.keymap.set('n', '<Leader>q', '<Cmd>copen<CR>')
vim.keymap.set('n', '<Leader>Q', '<Cmd>cclose<CR>')
vim.keymap.set('n', '<Leader>qj', '<Cmd>try | cnext | catch | cfirst | catch | endtry<CR>')
vim.keymap.set('n', '<Leader>qk', '<Cmd>try | cprevious | catch | clast | catch | endtry<CR>')
--- Format buffer
vim.keymap.set('n', '<Leader>ll', function() vim.lsp.buf.format { async = true } end, bufopts)
--- LSP (check :h lsp-defaults for default lsp bindings)
vim.keymap.set('n', 'grd', vim.lsp.buf.definition, bufopts)
vim.keymap.set('n', 'grD', vim.lsp.buf.declaration, bufopts)
-- Open diagnostic in a floating window
vim.keymap.set('n', '<Leader>le', function() vim.diagnostic.open_float(nil, { focus = false }) end, bufopts)
-- Show/hide diagnostic
vim.keymap.set('n', '<Leader>ts', vim.diagnostic.show, bufopts)
vim.keymap.set('n', '<Leader>th', vim.diagnostic.hide, bufopts)
-- Move to prev/next item
vim.keymap.set('n', 'åd', vim.diagnostic.goto_prev, bufopts)
vim.keymap.set('n', '¨d', vim.diagnostic.goto_next, bufopts)
