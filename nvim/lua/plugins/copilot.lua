-- The language server embedded in the plugin, not the one `npx` fetches. copilot.vim
-- prefers npx whenever it is on PATH, which quietly bypasses the copy this config
-- ad-hoc signs (see nvim.nix) for a copy under ~/.npm that is not signed at all -- and
-- an unsigned bundle has no stable identity for the keychain to remember, so every fresh
-- editor asks for a Copilot login again. Pinning to the embedded server is also why the
-- signing in nvim.nix has any effect.
vim.g.copilot_version = false

vim.g.copilot_no_tab_map = true
-- Use Shift-Tab to accept suggestions from copilot. So that we don't conflict with
-- copilot chat
vim.keymap.set("i", "<S-Tab>", 'copilot#Accept("\\<S-Tab>")', { expr = true, replace_keycodes = false })
