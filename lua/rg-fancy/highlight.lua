local M = {}

local api = vim.api

local ns = api.nvim_create_namespace("NaughieRgFancyHl")

local default_hl = {
    input_hint = { link = "Comment" },
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
    path = "RgFancyPath",
    line_idx = "RgFancyLineNr",
    cursor_line_idx = "RgFancyCursorLineNr",
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
    M.set_extmark[key] = function(buf, range)
        local opts = {
            end_row = range.end_line,
            end_col = range.end_col,
            hl_group = hl,
        }
        if range.hl_eol then opts.hl_eol = true end

        api.nvim_buf_set_extmark(buf, ns, range.start_line, range.start_col, opts)
    end
end

M.set_extmark.line_idx = function(buf, virt_text, to)
    api.nvim_buf_set_extmark(buf, ns, to, 0, {
        virt_text = { { virt_text, hl_names.line_idx } },
        virt_text_pos = "inline",
        right_gravity = false,
    })
end
M.set_extmark.cursor_line_idx = function(buf, virt_text, to)
    api.nvim_buf_set_extmark(buf, ns, to, 0, {
        virt_text = { { virt_text, hl_names.cursor_line_idx } },
        virt_text_pos = "inline",
        right_gravity = false,
    })
end
M.set_extmark.count = function(buf, virt_text, to)
    api.nvim_buf_set_extmark(buf, ns, to, 0, {
        virt_text = { { virt_text, hl_names.cursor_line_idx } },
        virt_text_pos = "eol",
        right_gravity = false,
    })
end

M.clear_extmarks = function(buf)
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
end

return M
