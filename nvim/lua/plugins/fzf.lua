local fzf = require('fzf-lua')
fzf.setup({
  fzf_colors = true,
  winopts = {
    width = 0.9,
    height = 0.9,
  },
  grep = {
    rg_opts = "--glob '!.git/*' --column --line-number --no-heading --color=always --smart-case --max-columns=4096 -e",
    hidden = true,
  },
})
vim.keymap.set('n', '<C-p>',
  function() fzf.files() end,
  { silent = true, desc = 'Search files with FZF' })
vim.keymap.set('n', '<C-e>',
  function() fzf.tags() end,
  { desc = 'Search ctags' })
vim.keymap.set('n', '<Leader>f',
  function() fzf.grep_project() end,
  { remap = true, silent = true, desc = 'Search text with ripgrep' })
