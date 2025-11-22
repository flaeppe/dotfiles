vim.lsp.config("pyright", {
    settings = {
        pyright = {
            -- Prefer Ruff's import organizer
            disableOrganizeImports = true,
        },
    },
})
vim.lsp.enable("pyright")
vim.lsp.config("ruff", {
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
vim.lsp.enable("ruff")
vim.lsp.enable("ts_ls")
vim.lsp.enable("graphql")
vim.lsp.config("gopls", {
    settings = {
        gopls = {
            staticcheck = true,
            gofumpt = true,
        }
    },
})
vim.lsp.enable("gopls")
vim.lsp.enable("golangci_lint_ls")
vim.lsp.enable("nixd")
vim.lsp.enable("lua_ls")
vim.lsp.enable("marksman")
