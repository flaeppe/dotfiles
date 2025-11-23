vim.g.copilot_no_tab_map = true
-- Use Shift-Tab to accept suggestions from copilot. So that we don't conflict with
-- copilot chat
vim.keymap.set("i", "<S-Tab>", 'copilot#Accept("\\<S-Tab>")', { expr = true, replace_keycodes = false })
