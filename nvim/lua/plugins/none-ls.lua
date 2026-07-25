local null_ls = require("null-ls")

-- sqruff discovers no configuration of its own -- it only reads --config -- so a
-- single fixed path forces one dialect on every project. A Postgres dialect met
-- with BigQuery SQL does not merely mis-lint: the file fails to parse, and an
-- unparsable file is reported as a violation on essentially every line. Prefer a
-- .sqruff sitting with the SQL, and fall back to the shared one.
local function sqruff_config(params)
    local found = vim.fs.find(".sqruff", {
        upward = true,
        type = "file",
        path = vim.fs.dirname(params.bufname),
    })[1]
    return found or (vim.env.HOME .. "/.sqruff")
end

-- dbt models are Jinja templates that happen to contain SQL. `{{ ref(...) }}` is
-- unparsable in every dialect, and sqruff ships only the raw and placeholder
-- templaters (`sqruff templaters`), so there is no configuration that makes
-- these files lintable -- running it just paints whole models red.
local function not_dbt_project(params)
    return vim.fs.find("dbt_project.yml", {
        upward = true,
        type = "file",
        path = vim.fs.dirname(params.bufname),
    })[1] == nil
end

null_ls.setup({
    sources = {
        null_ls.builtins.diagnostics.hadolint,
        null_ls.builtins.formatting.gofmt,
        null_ls.builtins.formatting.goimports,
        null_ls.builtins.formatting.nixfmt,
        -- SQL
        null_ls.builtins.diagnostics.sqruff.with({
            runtime_condition = not_dbt_project,
            args = function(params)
                return {
                    "--config",
                    sqruff_config(params),
                    "lint",
                    "--format",
                    "github-annotation-native",
                    "$FILENAME",
                }
            end,
        }),
        null_ls.builtins.formatting.sqruff.with({
            runtime_condition = not_dbt_project,
            args = function(params)
                return { "--config", sqruff_config(params), "fix", "-" }
            end,
        }),
        null_ls.builtins.formatting.stylua,
        null_ls.builtins.diagnostics.markdownlint,
        null_ls.builtins.formatting.markdownlint,
    },
})
