vim.filetype.add({
  extension = {
    typ = 'markdown',
  },
})
--- Navigation
local kitty_nav = require('kitty_nav')
vim.keymap.set('n', '<C-h>', function() kitty_nav.navigate('h') end)
vim.keymap.set('n', '<C-j>', function() kitty_nav.navigate('j') end)
vim.keymap.set('n', '<C-k>', function() kitty_nav.navigate('k') end)
vim.keymap.set('n', '<C-l>', function() kitty_nav.navigate('l') end)
--- Quicklist mappings
vim.keymap.set('n', '<Leader>q', '<Cmd>copen<CR>')
vim.keymap.set('n', '<Leader>Q', '<Cmd>cclose<CR>')
vim.keymap.set('n', '<Leader>qj', '<Cmd>try | cnext | catch | cfirst | catch | endtry<CR>')
vim.keymap.set('n', '<Leader>qk', '<Cmd>try | cprevious | catch | clast | catch | endtry<CR>')
--- Display available code actions
vim.keymap.set('n', '<Leader>ca', vim.lsp.buf.code_action, silent)
--- Format buffer
vim.keymap.set('n', '<Leader>ll', function() vim.lsp.buf.format { async = true } end, bufopts)
--- LSP
vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, bufopts)
vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bufopts)
vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, bufopts)
vim.keymap.set('n', 'gr', vim.lsp.buf.references, bufopts)
vim.keymap.set('n', '<Leader>rn', vim.lsp.buf.rename, bufopts)
-- Open diagnostic in a floating window
vim.keymap.set('n', '<Leader>le', function() vim.diagnostic.open_float(nil, { focus = false }) end, bufopts)
-- Show/hide diagnostic
vim.keymap.set('n', '<Leader>ts', vim.diagnostic.show, bufopts)
vim.keymap.set('n', '<Leader>th', vim.diagnostic.hide, bufopts)
-- Move to prev/next item
vim.keymap.set('n', 'åd', vim.diagnostic.goto_prev, bufopts)
vim.keymap.set('n', '¨d', vim.diagnostic.goto_next, bufopts)
-- Diagnostic settings
vim.diagnostic.config({
  update_in_insert = true,
  float = {
    focusable = false,
    style = "minimal",
    border = "rounded",
    source = "always",
    header = "",
    prefix = "",
  },
})
-- Define a custom command that opens NERDTree and then moves to the buffer on
-- the right. Used when starting nvim
vim.api.nvim_create_user_command('OpenTreeAndJump', function()
  vim.cmd('vsplit')
  vim.cmd('NERDTreeToggle')
  -- Ensure the cursor is in the buffer window, not the NERDTree window
  -- If NERDTree opens on the left, the buffer window is on the right
  if vim.fn.bufexists(vim.fn.bufname('%')) then -- Check if there's an actual buffer
    vim.cmd('wincmd l') -- Move to the window on the right
  end
  vim.cmd('normal! <C-w>=') -- Resize
end, {})
