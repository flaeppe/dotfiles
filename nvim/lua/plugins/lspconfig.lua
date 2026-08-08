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
-- TypeScript via vtsls rather than ts_ls: it exposes the tsserver commands the
-- plain LSP surface has no request for, notably goToSourceDefinition below.
vim.lsp.config("vtsls", {
    settings = {
        vtsls = {
            -- Use the TypeScript version the repo pins instead of the one
            -- bundled with vtsls, so resolution matches what tsc and CI see.
            autoUseWorkspaceTsdk = true,
            experimental = {
                completion = { enableServerSideFuzzyMatch = true },
            },
        },
        typescript = {
            -- tsserver's default heap is sized for a single package; a
            -- workspace-wide project graph exhausts it and the server dies
            -- mid-session, which reads as "the LSP stopped working".
            tsserver = { maxTsServerMemory = 8192 },
            preferences = {
                -- Offer auto-imports from every package in the workspace, not
                -- only the ones the open file already reaches.
                includePackageJsonAutoImports = "on",
                -- Prefer a project-relative import over a long ../../.. chain.
                importModuleSpecifier = "shortest",
            },
            -- Inert unless inlay hints are switched on (<Leader>ti).
            inlayHints = {
                parameterNames = { enabled = "literals" },
                variableTypes = { enabled = true },
                functionLikeReturnTypes = { enabled = true },
            },
        },
    },
})
vim.lsp.enable("vtsls")
-- In a workspace, an import resolves to the generated .d.ts, so plain
-- go-to-definition lands on a type declaration rather than the code that
-- implements it. Only tsserver knows the mapping back to source.
vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if not client or client.name ~= "vtsls" then
            return
        end
        vim.keymap.set("n", "grs", function()
            local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
            client:request("workspace/executeCommand", {
                command = "typescript.goToSourceDefinition",
                arguments = { params.textDocument.uri, params.position },
            }, function(err, locations)
                if err or not locations or vim.tbl_isempty(locations) then
                    return vim.lsp.buf.definition()
                end
                vim.lsp.util.show_document(locations[1], client.offset_encoding, { focus = true })
            end, args.buf)
        end, { buffer = args.buf, desc = "Go to source definition (past .d.ts)" })
    end,
})
-- A rename edits every file that referenced the symbol and leaves all of them
-- unwritten, which turns one decision into a pile of buffers to remember. The
-- edits only exist once the request reports complete, so the write hangs off
-- that rather than off the call returning.
vim.keymap.set("n", "grn", function()
    vim.api.nvim_create_autocmd("LspRequest", {
        group = vim.api.nvim_create_augroup("RenameWriteAll", { clear = true }),
        callback = function(args)
            local request = args.data.request
            if request.method ~= "textDocument/rename" or request.type ~= "complete" then
                return
            end
            -- Scheduled, not immediate: the event is emitted from the reply
            -- callback, which runs before the handler that applies the edit.
            vim.schedule(function()
                -- Fails on an unnamed buffer, which no rename can have touched.
                local ok, err = pcall(vim.cmd, "wall")
                if not ok then
                    vim.notify(tostring(err), vim.log.levels.WARN)
                end
            end)
            return true
        end,
    })
    vim.lsp.buf.rename()
end, { desc = "Rename symbol, then write every file it touched" })

-- lspconfig's default filetypes are { graphql, typescriptreact,
-- javascriptreact }, so operations written in plain .ts/.js modules -- hooks,
-- server-side resolvers, generated clients -- get no GraphQL LSP at all.
-- Attaching still requires a graphql-config file at the project root.
vim.lsp.config("graphql", {
    filetypes = { "graphql", "typescript", "typescriptreact", "javascript", "javascriptreact" },
})
vim.lsp.enable("graphql")
vim.lsp.config("gopls", {
    settings = {
        gopls = {
            staticcheck = true,
            gofumpt = true,
            -- Symbol search spans loaded dependencies, and reports each hit as
            -- pkg.Symbol so the picker can tell apart the same name defined in
            -- several packages.
            symbolScope = "all",
            symbolStyle = "Package",
            symbolMatcher = "FastFuzzy",
            -- Keep the JS and Python trees of a polyglot repo out of gopls'
            -- view; scanning them costs startup time and returns nothing.
            directoryFilters = { "-**/node_modules", "-**/.direnv", "-**/.venv" },
            -- .tmpl/.gotmpl are mapped to the gotmpl filetype in autocmds.lua,
            -- but gopls only analyses templates whose extension is listed here.
            templateExtensions = { "tmpl", "gotmpl" },
            analyses = {
                nilness = true,
                unusedparams = true,
                unusedwrite = true,
                unusedvariable = true,
                useany = true,
            },
            -- Inert unless inlay hints are switched on (<Leader>ti).
            hints = {
                assignVariableTypes = true,
                compositeLiteralFields = true,
                constantValues = true,
                functionTypeParameters = true,
                parameterNames = true,
                rangeVariableTypes = true,
            },
        },
    },
})
vim.lsp.enable("gopls")
vim.lsp.enable("golangci_lint_ls")
-- Parses SQL with Postgres' own grammar rather than a regex dialect guess, so
-- CTEs and modern syntax resolve. Only attaches where a
-- postgres-language-server.jsonc marks the project as configured.
vim.lsp.enable("postgres_lsp")
vim.lsp.enable("nixd")
vim.lsp.enable("lua_ls")
vim.lsp.enable("marksman")
