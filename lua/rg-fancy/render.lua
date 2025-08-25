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

    local max_line_idx_width = 0

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

            local line_idx_width = vim.fn.strwidth(line_idx)
            max_line_idx_width = math.max(max_line_idx_width, line_idx_width)
        end,

        append_after = function(total_lines)
            api.nvim_buf_set_lines(buf, total_lines, -1, false, lines)
            for _, ext in ipairs(exts) do
                if ext.hl_group == "line_idx" or ext.hl_group == "cursor_line_idx" then
                    local pad = string.rep(" ", max_line_idx_width - vim.fn.strwidth(ext.line_idx))
                    local virt_text = pad .. ext.line_idx .. "│  "
                    if ext.hl_group == "cursor_line_idx" then
                        virt_text = " \u{ee83} " .. virt_text
                    else
                        virt_text = "   " .. virt_text
                    end
                    hl.set_extmark[ext.hl_group](buf, virt_text, ext.to + total_lines)
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

local function render_result_path(path, renderer, input)
    local trunc = path
    if string.find(path, input.cwd, 1, true) == 1 then
        trunc = string.sub(path, #input.cwd + 2)
    end
    renderer.insert_line(" \u{f4ec} " .. trunc, "path")
end

local function render_error(result, renderer, input)
    if result.path and result.path ~= vim.NIL then
        render_result_path(result.path, renderer, input)
    end

    renderer.insert_line("")
    renderer.insert_line(" \u{f421} " .. result.error, "error")
end

local function render_matched(result, renderer, input)
    render_result_path(result.path, renderer, input)

    local base_line = nil
    if result.line_idx and result.line_idx ~= vim.NIL then
        base_line = result.line_idx
    end

    renderer.insert_line("")

    for i = #result.before, 1, -1 do
        local line_idx = tostring(base_line - i)
        local item = result.before[i]
        if item and item ~= vim.NIL then
            renderer.insert_line(item, "context")
            renderer.set_line_idx(line_idx)
        end
    end

    if result.matched and result.matched ~= vim.NIL then
        for _, matched_line in ipairs(result.matched) do
            local line_idx = tostring(base_line)

            renderer.insert_line(matched_line, "matched")
            renderer.set_line_idx(line_idx, true)

            base_line = base_line + 1
        end
    end

    for i, item in ipairs(result.after) do
        local line_idx = tostring(base_line + i - 1)
        if item and item ~= vim.NIL then
            renderer.insert_line(item, "context")
            renderer.set_line_idx(line_idx)
        end
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
        "\u{e370} Grep summary\u{e370}",
        "    \u{f422} #matches \u{f061} " .. tostring(count),
        "    \u{f034e} Path \u{f061} " .. input.path,
        "    \u{f0451} Pattern \u{f061} " .. input.pattern,
    }
    api.nvim_buf_set_lines(buf, 0, -1, false,  header)
    hl.set_extmark.header(buf, {
        start_line = 0,
        end_line = #header,
        start_col = 0,
        end_col = 0,
        hl_eol = true,
    })

    return #header
end

function M.results(buf, results, input)
    states.results.set(results)

    local win_width = api.nvim_win_get_width(0)

    api.nvim_set_option_value("modifiable", true, { buf = buf })

    hl.clear_extmarks(buf)
    local total_lines = render_header(buf, results, input, win_width)
    for _, result in ipairs(results) do
        local renderer = create_file_renderer(buf)

        local sep = string.rep("─", win_width)
        renderer.insert_line(sep, "separator")

        if result.error and result.error ~= vim.NIL then
            render_error(result, renderer, input)
        else
            render_matched(result, renderer, input)
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
