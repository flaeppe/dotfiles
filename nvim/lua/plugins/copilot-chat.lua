vim.keymap.set("n", "<Leader>cc", function()
    -- Split to the right and open Copilot Chat in the new split
    vim.cmd("rightbelow vsplit")
    require("CopilotChat").open({ window = { layout = "replace" } })
end, { noremap = true, silent = true, desc = "Open Copilot Chat" })
local chat = require("CopilotChat")
chat.setup({
    mappings = {
        close = {
            -- Disable the default closing(<C-c>) in insert mode
            insert = false,
        },
    },
})
