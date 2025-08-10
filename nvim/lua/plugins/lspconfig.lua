local lspconfig = require("lspconfig")
lspconfig.pyright.setup({
    settings = {
        pyright = {
            -- Prefer Ruff's import organizer
            disableOrganizeImports = true,
        },
    },
})
lspconfig.ruff.setup({
    commands = {
        RuffAutofix = {
            function()
                vim.lsp.buf.code_action({
                    context = {
                        only = { "source.fixAll.ruff" },
                    },
                    apply = true,
                })
            end,
            description = "Ruff: Fix all auto-fixable problems",
        },
        RuffOrganizeImports = {
            function()
                vim.lsp.buf.code_action({
                    context = {
                        only = { "source.organizeImports.ruff" },
                    },
                    apply = true,
                })
            end,
            description = "Ruff: Format imports",
        },
    },
})
lspconfig.ts_ls.setup({})
lspconfig.graphql.setup({})
lspconfig.gopls.setup({})
lspconfig.golangci_lint_ls.setup({})
lspconfig.nixd.setup({})
lspconfig.lua_ls.setup({})
