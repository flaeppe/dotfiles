-- Only load if not already loaded or if not in compatibility mode
if vim.g.loaded_kitty_navigator or vim.opt.cp:get() then
  return
end
vim.g.loaded_kitty_navigator = true


local function vim_navigate(direction)
  pcall(function()
    vim.cmd('wincmd ' .. direction)
  end)
end


local M = {}


function M.navigate(direction)
  local initialWindow = vim.fn.winnr()
  -- Try moving in direction
  vim_navigate(direction)
  -- See if window moved within nvim
  local at_tab_page_edge = (initialWindow == vim.fn.winnr())
  if at_tab_page_edge then
    local mappings = {
      h = "left",
      j = "bottom",
      k = "top",
      l = "right"
    }
    local cmd = 'kitty @ kitten chained_nav.py ' .. mappings[direction]
    pcall(function()
      vim.fn.system(cmd)
    end)
  end
end

return M
