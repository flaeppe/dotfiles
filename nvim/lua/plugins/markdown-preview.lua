-- Only render markdown files; auto-close the browser tab when the buffer is left
vim.g.mkdp_filetypes = { "markdown" }
vim.g.mkdp_auto_close = 1

-- On i3, mkdp opens the preview as a tab in the existing browser instance
-- without switching to its workspace, so jump there ourselves when we just
-- opened. Skipped wherever i3-msg isn't present (e.g. macOS).
vim.keymap.set("n", "<Leader>mp", function()
    vim.cmd("MarkdownPreviewToggle")
    if vim.b.MarkdownPreviewToggleBool == 1 and vim.fn.executable("i3-msg") == 1 then
        vim.fn.jobstart({ "i3-msg", "[class=\"Chromium\"] focus" }, { detach = true })
    end
end)
