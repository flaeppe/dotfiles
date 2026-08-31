vim.g.NERDTreeIgnore = {
    "\\.pyc$",
    "__pycache__",
    "\\.js.map$",
    "\\.DS_STORE",
    "venv",
    "\\.mypy_cache",
    "\\.pytest_cache",
    "\\.nox",
    "\\.egg-info$",
    "\\.tags",
    -- Directories that are never the thing you are browsing for, and that cost
    -- a screen of scrolling each because hidden files are shown below.
    "node_modules[[dir]]",
    "\\.git$[[dir]]",
    "\\.direnv[[dir]]",
    "\\.worktrees[[dir]]",
    "\\.ruff_cache[[dir]]",
    "\\.next[[dir]]",
    "coverage[[dir]]",
    "dist[[dir]]",
}
-- Show hidden files and folders per default in file browser
vim.g.NERDTreeShowHidden = 1
-- Keymaps
vim.keymap.set("n", "<Leader>nn", ":NERDTreeToggle<CR>")
vim.keymap.set("n", "<Leader>nf", ":NERDTreeFind<CR>")
