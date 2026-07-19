-- nvim-treesitter (main branch): parsers are provided by Nix via
-- `withAllGrammars`, so no install step is needed here. Highlighting is a
-- native Neovim feature (vim.treesitter.start); indentation comes from the
-- plugin's indentexpr. Enable both per-buffer for any filetype with a parser.
vim.api.nvim_create_autocmd("FileType", {
    callback = function(args)
        if pcall(vim.treesitter.start, args.buf) then
            vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
    end,
})
