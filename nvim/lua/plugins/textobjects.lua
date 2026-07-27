-- Structural motion and selection. Treesitter resolves these against the
-- innermost language at the cursor, so they work inside injected gql`...` and
-- sql`...` blocks in TypeScript too, not only in the host language.
--
-- ]c/[c are left alone -- gitsigns owns them for hunk motion.
require("nvim-treesitter-textobjects").setup({
    select = {
        -- Act on the next textobject when the cursor sits between two.
        lookahead = true,
    },
    move = { set_jumps = true },
})

local select = require("nvim-treesitter-textobjects.select")
local move = require("nvim-treesitter-textobjects.move")

local textobjects = {
    af = "@function.outer",
    ["if"] = "@function.inner",
    at = "@class.outer",
    it = "@class.inner",
    aa = "@parameter.outer",
    ia = "@parameter.inner",
}
for lhs, query in pairs(textobjects) do
    vim.keymap.set({ "x", "o" }, lhs, function()
        select.select_textobject(query, "textobjects")
    end, { desc = "Select " .. query })
end

local motions = {
    ["]f"] = { move.goto_next_start, "@function.outer" },
    ["[f"] = { move.goto_previous_start, "@function.outer" },
    ["]F"] = { move.goto_next_end, "@function.outer" },
    ["[F"] = { move.goto_previous_end, "@function.outer" },
    ["]t"] = { move.goto_next_start, "@class.outer" },
    ["[t"] = { move.goto_previous_start, "@class.outer" },
}
for lhs, spec in pairs(motions) do
    local goto_fn, query = spec[1], spec[2]
    vim.keymap.set({ "n", "x", "o" }, lhs, function()
        goto_fn(query, "textobjects")
    end, { desc = "Move to " .. query })
end
