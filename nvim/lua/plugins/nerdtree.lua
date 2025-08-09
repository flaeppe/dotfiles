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
}
-- Show hidden files and folders per default in file browser
vim.g.NERDTreeShowHidden = 1
-- Keymaps
vim.keymap.set("n", "<Leader>nn", ":NERDTreeToggle<CR>")
vim.keymap.set("n", "<Leader>nf", ":NERDTreeFind<CR>")
