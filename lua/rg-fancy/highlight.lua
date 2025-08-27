local M = {}

local api = vim.api

local ns = api.nvim_create_namespace("NaughieRgFancyHl")

local default_hl = {
    input_hint = { link = "Comment" },
    input_hint_notice = { link = "Comment" },
    path = { link = "Directory" },
    line_idx = { link = "LineNr" },
    cursor_line_idx = { link = "CursorLineNr" },
    count = { link = "Comment" },
    context = { link = "Comment" },
    matched = { link = "Search" },
    error = { link = "Error" },
    separator = { link = "FloatBorder" },
    header = { link = "Normal" },
}

local hl_names = {
    input_hint = "RgFancyInputHint",
    input_hint_notice = "RgFancyInputHintNotice",
    path = "RgFancyPath",
    line_idx = "RgFancyLineNr",
    cursor_line_idx = "RgFancyCursorLineNr",
    count = "RgFancyCount",
    context = "RgFancyContext",
    matched = "RgFancyMatched",
    error = "RgFancyError",
    separator = "RgFancySeparator",
    header = "RgFancyHeader",
}
M.hl_groups = hl_names

function M.set_highlight_groups(opts)
    for key, hl in pairs(hl_names) do
        if opts and opts[key] then
            api.nvim_set_hl(0, hl, opts[key])
        else
            api.nvim_set_hl(0, hl, default_hl[key])
        end
    end
end

M.set_extmark = {}

for key, hl in pairs(hl_names) do
    M.set_extmark[key] = function(buf, args)
        if args.virt_text then
            local opts = {
                virt_text = { { args.virt_text, hl } },
                virt_text_pos = args.pos,
                -- right_gravity = false,
            }

            api.nvim_buf_set_extmark(buf, ns, args.line, args.col, opts)
        else
            local opts = {
                end_row = args.end_line,
                end_col = args.end_col,
                hl_group = hl,
            }
            if args.hl_eol then opts.hl_eol = true end

            api.nvim_buf_set_extmark(buf, ns, args.start_line, args.start_col, opts)
        end
    end
end

M.clear_extmarks = function(buf)
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
end

return M
