-- nvim-treesitter (main branch): parsers are provided by Nix via a curated
-- `withPlugins` grammar list (see nvim.nix), so no install step is needed
-- here. Highlighting is a native Neovim feature (vim.treesitter.start);
-- indentation comes from the plugin's indentexpr. Enable both per-buffer for
-- any filetype with a parser, so buffers outside the curated list still fall
-- back to Vim's regex-based syntax highlighting via pcall.
vim.api.nvim_create_autocmd("FileType", {
    callback = function(args)
        if pcall(vim.treesitter.start, args.buf) then
            vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
    end,
})
