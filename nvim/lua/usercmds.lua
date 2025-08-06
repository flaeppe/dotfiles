-- User command for formatting JSON
vim.api.nvim_create_user_command('FormatJSON', '<line1>,<line2>!jq .', {
  range = true, -- Allows using a range (e.g., :%FormatJSON)
  desc = 'Format JSON content using jq',
})
-- Define a user command that opens NERDTree and then moves to the buffer on
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
