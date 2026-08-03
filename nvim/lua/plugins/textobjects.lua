-- Structural motion and selection. Treesitter resolves these against the
-- innermost language at the cursor, so they work inside injected gql`...` and
-- sql`...` blocks in TypeScript too, not only in the host language.
--
-- Motion pairs are ¨/å rather than ]/[: on a Nordic Mac layout `[` is Option+8
-- and `]` is Option+9, which puts a modifier in front of a motion meant to be
-- pressed repeatedly. ¨ and å are unmodified keys sitting in those same physical
-- positions, so the ]->¨ (next) and [->å (previous) reading stays intact.
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
    ["¨f"] = { move.goto_next_start, "@function.outer" },
    ["åf"] = { move.goto_previous_start, "@function.outer" },
    ["¨F"] = { move.goto_next_end, "@function.outer" },
    ["åF"] = { move.goto_previous_end, "@function.outer" },
    ["¨t"] = { move.goto_next_start, "@class.outer" },
    ["åt"] = { move.goto_previous_start, "@class.outer" },
}
for lhs, spec in pairs(motions) do
    local goto_fn, query = spec[1], spec[2]
    vim.keymap.set({ "n", "x", "o" }, lhs, function()
        goto_fn(query, "textobjects")
    end, { desc = "Move to " .. query })
end
