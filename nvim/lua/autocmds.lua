-- Whitespace trimming function and autocommand
local trim_augroup = vim.api.nvim_create_augroup("TrimWhitespace", { clear = true })

-- Autocommand to remove whitespace before writing a buffer
vim.api.nvim_create_autocmd("BufWritePre", {
    group = trim_augroup,
    pattern = "",
    command = ":%s/\\s\\+$//e",
})
