local M = {}

local hl = require("rg-fancy.highlight")

local mkstate = require("glocal-states")

local states = {
    results = mkstate.tab(),
}

local api = vim.api

local virt_ns = api.nvim_create_namespace("NaughieRgFancyVirt")

function M.input(buf)
    api.nvim_buf_clear_namespace(buf, virt_ns, 0, -1)

    api.nvim_buf_set_lines(buf, 0, -1, false, { ".", "" })

    api.nvim_buf_set_extmark(buf, virt_ns, 0, 0, {
        virt_text = { { " \u{eb05} Path    \u{f101} ", hl.hl_groups.input_hint } },
        virt_text_pos = "inline",
        right_gravity = false,
    })
    api.nvim_buf_set_extmark(buf, virt_ns, 1, 0, {
        virt_text = { { " \u{eb05} Pattern \u{f101} ", hl.hl_groups.input_hint } },
        virt_text_pos = "inline",
        right_gravity = false,
    })
end

local function create_file_renderer(buf)
    local lines = {}
    local exts = {}

    return {
        insert_line = function(line, hl_group)
            table.insert(lines, line)
            if hl_group then
                table.insert(exts, {
                    start_line = #lines - 1,
                    end_line = #lines - 1,
                    start_col = 0,
                    end_col = string.len(line),
                    hl_group = hl_group,
                })
            end
        end,

        set_line_idx = function(line_idx, cursor)
            if cursor then
                table.insert(exts, {
                    line_idx = line_idx,
                    to = #lines - 1,
                    hl_group = "cursor_line_idx",
                })
            else
                table.insert(exts, {
                    line_idx = line_idx,
                    to = #lines - 1,
                    hl_group = "line_idx",
                })
            end
        end,

        append_after = function(total_lines)
            api.nvim_buf_set_lines(buf, total_lines, -1, false, lines)
            for _, ext in ipairs(exts) do
                if ext.hl_group == "line_idx" or ext.hl_group == "cursor_line_idx" then
                    hl.set_extmark[ext.hl_group](buf, ext.line_idx, ext.to + total_lines)
                else
                    hl.set_extmark[ext.hl_group](buf, {
                        start_line = ext.start_line + total_lines,
                        end_line = ext.end_line + total_lines,
                        start_col = ext.start_col,
                        end_col = ext.end_col,
                    })
                end
            end
            return total_lines + #lines
        end,
    }
end

local function render_error(result, renderer)
    renderer.insert_line(result.path, "path")
    if result.path and result.path ~= vim.NIL then
        renderer.insert_line(result.path, "path")
    end
    renderer.insert_line(result.error, "error")
end

local function render_matched(result, renderer)
    renderer.insert_line(result.path, "path")

    local base_line = nil
    if result.line_idx and result.line_idx ~= vim.NIL then
        base_line = result.line_idx
    end

    renderer.insert_line("")

    if result.before[1] and result.before[1] ~= vim.NIL then
        local line_idx = tostring(base_line - 1)
        if result.before[2] and result.before[2] ~= vim.NIL then
            line_idx = tostring(base_line - 2)
        end

        renderer.insert_line(result.before[1], "context")
        renderer.set_line_idx(line_idx)
    end
    if result.before[2] and result.before[2] ~= vim.NIL then
        local line_idx = tostring(base_line - 1)

        renderer.insert_line(result.before[2], "context")
        renderer.set_line_idx(line_idx)
    end

    if result.matched and result.matched ~= vim.NIL then
        for _, matched_line in ipairs(result.matched) do
            local line_idx = tostring(base_line)

            renderer.insert_line(matched_line, "matched")
            renderer.set_line_idx(line_idx, true)

            base_line = base_line + 1
        end
    end

    if result.after[1] and result.after[1] ~= vim.NIL then
        local line_idx = tostring(base_line)

        renderer.insert_line(result.after[1], "context")
        renderer.set_line_idx(line_idx)
    end
    if result.after[2] and result.after[2] ~= vim.NIL then
        local line_idx = tostring(base_line + 1)

        renderer.insert_line(result.after[2], "context")
        renderer.set_line_idx(line_idx)
    end
end

local function render_header(buf, results, input, win_width)
    local count = 0
    for _, result in ipairs(results) do
        if not result.error or result.error == vim.NIL then
            count = count + 1
        end
    end

    local header = {
        "Grep summary",
        "    #matches: " .. tostring(count),
        "    Path: " .. input.path,
        "    Pattern: " .. input.pattern,
    }

    local rendered = {}
    for _, header_line in ipairs(header) do
        local rest = string.rep(" ", win_width - vim.fn.strwidth(header_line))
        table.insert(rendered, header_line .. rest)
    end
    api.nvim_buf_set_lines(buf, 0, -1, false,  rendered)
    hl.set_extmark.header(buf, {
        start_line = 0,
        end_line = #header,
        start_col = 0,
        end_col = 0,
    })

    return #header
end

function M.results(buf, results, input)
    states.results.set(results)

    local win_width = api.nvim_win_get_width(0)

    api.nvim_set_option_value("modifiable", true, { buf = buf })

    local total_lines = render_header(buf, results, input, win_width)
    for _, result in ipairs(results) do
        local renderer = create_file_renderer(buf)

        local sep = string.rep("─", win_width)
        renderer.insert_line(sep, "separator")

        if result.error and result.error ~= vim.NIL then
            render_error(result, renderer)
        else
            render_matched(result, renderer)
        end

        total_lines = renderer.append_after(total_lines)
    end

    api.nvim_set_option_value("modifiable", false, { buf = buf })
end

M.manipulate = {
    input = {
        move_to_next_eol = function(win, buf)
            local curr_pos = api.nvim_win_get_cursor(win)

            local next_row = curr_pos[1] + 1
            if next_row > 2 then
                next_row = 1
            end

            local next_lines = api.nvim_buf_get_lines(buf, next_row - 1, next_row, false)
            if #next_lines == 0 then return end
            local next_line = next_lines[1]

            api.nvim_win_set_cursor(win, { next_row, #next_line + 1 })
        end,

        get = function(buf)
            local lines = api.nvim_buf_get_lines(buf, 0, 2, false)
            if #lines ~= 2 then return end

            return {
                path = lines[1],
                pattern = lines[2],
            }
        end,
    },
}

M.props = {
    input_geom = { height = 2 },
}

return M
