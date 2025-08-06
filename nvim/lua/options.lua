-- Map the leader key to SPACE
vim.g.mapleader = ' '
-- Render TABs using this many spaces
vim.opt.tabstop = 2
-- Indentation amount for < and > commands
vim.opt.shiftwidth = 2
-- Number of spaces that Tab keypress or Backspace keypress will insert/delete
vim.opt.softtabstop = 2
-- Insert spaces instead of tab characters
vim.opt.expandtab = true
-- Makes Tab and Backspace keys behave intelligently for indentation at the start of lines
vim.opt.smarttab = true
-- Show line numbers
vim.opt.number = true
-- Disable error bells
vim.opt.errorbells = false
-- Use the system clipboard
vim.opt.clipboard = 'unnamedplus'
-- Relative line number on by default
vim.opt.relativenumber = true
-- Disable mouse
vim.opt.mouse = ''
-- Enable true colors support
vim.opt.termguicolors = true
-- Always display statusbar
vim.opt.laststatus = 2
-- What the status bar should look like
vim.opt.statusline = '%-10.3n ' ..    -- %-10.3n: Buffer number, left-aligned, max 10 chars, min 3 chars
                     '%f ' ..         -- %f: Full path to the file
                     '%h%m%r%w ' ..   -- %h: Help file flag, %m: Modified flag, %r: Readonly flag, %w: Preview window flag
                     '[%{strlen(&ft)?&ft:\'none\'}] ' .. -- %{...}: Evaluate expression. Shows filetype or 'none' if empty.
                     '%=' ..          -- %=: Right-aligns the following items
                     '0x%-8B ' ..     -- 0x%-8B: Character value under cursor in hex, left-aligned, max 8 chars
                     '%-14(%l,%c%V%) ' .. -- %-14(...): Grouped items, left-aligned, max 14 chars.
                                          -- %l: Current line number
                                          -- %c: Current column number
                                          -- %V: Virtual column number (byte index in line)
                     '%<%P'           -- %<%P: File position as percentage, truncated if too long
-- Disable unused providers
vim.g.loaded_perl_provider = 0
