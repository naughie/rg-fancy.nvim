local M = {}

local hl = require("rg-fancy.highlight")

local mkstate = require("glocal-states")

local states = {
    results = mkstate.tab(),
}

local api = vim.api

local virt_ns = api.nvim_create_namespace("NaughieRgFancyVirt")

local input_height = 3
function M.input(buf)
    api.nvim_buf_clear_namespace(buf, virt_ns, 0, -1)

    api.nvim_buf_set_lines(buf, 0, -1, false, { ".", "", "" })

    api.nvim_buf_set_extmark(buf, virt_ns, 0, 0, {
        virt_text = { { " \u{eb05} Path             \u{f101} ", hl.hl_groups.input_hint } },
        virt_text_pos = "inline",
        right_gravity = false,
    })
    api.nvim_buf_set_extmark(buf, virt_ns, 1, 0, {
        virt_text = { { " \u{eb05} Pattern          \u{f101} ", hl.hl_groups.input_hint } },
        virt_text_pos = "inline",
        right_gravity = false,
    })
    api.nvim_buf_set_extmark(buf, virt_ns, 2, 0, {
        virt_text = { { " \u{eb05} Glob (whitelist) \u{f101} ", hl.hl_groups.input_hint } },
        virt_text_pos = "inline",
        right_gravity = false,
    })
    api.nvim_buf_set_extmark(buf, virt_ns, 2, 0, {
        virt_lines = { { { '     \u{f1fd} Space separated glob, defaults to !**/.git', hl.hl_groups.input_hint_notice } } },
    })
end

local function create_result_renderer(buf)
    local lines = {}
    local exts = {}

    local inner_states = { path = nil, base_line = nil, offset = nil }
    local line_idx_exts = {}

    local max_line_idx_width = 0

    local states_idx = nil

    local make_line_idx_virt_text = function(line_idx, cursor)
        local pad = string.rep(" ", max_line_idx_width - vim.fn.strwidth(line_idx))
        local virt_text = pad .. line_idx .. "│"
        if cursor then
            virt_text = " \u{ee83} " .. virt_text
        else
            virt_text = "   " .. virt_text
        end
        return virt_text
    end

    local insert_line = function(line, hl_group)
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
    end

    local insert_virt_text = function(virt_text, hl_group, opts)
        local ext_args = opts
        ext_args.virt_text = virt_text
        ext_args.to = #lines - 1
        ext_args.hl_group = hl_group

        table.insert(exts, ext_args)
    end

    return {
        insert_line = insert_line,

        set_base_line_idx = function(line_idx)
            inner_states.base_line = line_idx
        end,

        set_offset = function(offset)
            inner_states.offset = offset
        end,

        set_virt_text = function(virt_text, hl_group, opts)
            insert_virt_text(virt_text, hl_group, opts or { pos = "inline", col = 0 })
        end,

        set_line_idx = function(line_idx, cursor)
            local hl_group = "line_idx"
            if cursor then hl_group = "cursor_line_idx" end

            if cursor then
                insert_virt_text(" ", "empty", {
                    pos = "inline",
                    col = 0,
                })
            else
                insert_virt_text("  ", "empty", {
                    pos = "inline",
                    col = 0,
                })
            end

            insert_virt_text(function()
                return make_line_idx_virt_text(line_idx, cursor)
            end, hl_group, {
                pos = "inline",
                col = 0,
            })

            local line_idx_width = vim.fn.strwidth(line_idx)
            max_line_idx_width = math.max(max_line_idx_width, line_idx_width)
        end,

        set_tick_around = function(start_col, end_col, hl_group)
            insert_virt_text("\u{e0b6}", hl_group, {
                pos = "inline",
                col = start_col,
            })
            insert_virt_text("\u{e0b4}", hl_group, {
                pos = "inline",
                col = end_col,
            })
        end,

        set_path = function(path, cwd, count)
            local trunc = path
            if string.find(path, cwd, 1, true) == 1 then
                trunc = string.sub(path, #cwd + 2)
            end
            insert_line(trunc, "path")
            inner_states.path = path
            insert_virt_text(" \u{f4ec} ", "path", {
                pos = "inline",
                col = 0,
            })

            if count then
                local virt_text = string.format("  \u{f0d08} (%d/%d)", count.current, count.total)
                insert_virt_text(virt_text, "count", {
                    pos = "eol",
                    col = 0,
                })
            end
        end,

        update_states = function(total_lines)
            local current_states = states.results.get()
            if current_states then
                current_states.items[total_lines] = inner_states
                current_states.final_idx = total_lines
            else
                local new_states = { items = {}, final_idx = total_lines }
                new_states.items[total_lines] = inner_states
                states.results.set(new_states)
            end

            states_idx = total_lines
        end,

        update_line_idx_states = function()
            local current_states = states.results.get()
            current_states.items[states_idx].line_idx_exts = line_idx_exts
        end,

        append_after = function(total_lines)
            api.nvim_buf_set_lines(buf, total_lines, -1, false, lines)
            for _, ext in ipairs(exts) do
                if ext.virt_text then
                    local virt_text = ext.virt_text
                    if type(ext.virt_text) == "function" then
                        virt_text = ext.virt_text()
                    end

                    local ext_id = hl.set_extmark[ext.hl_group](buf, {
                        virt_text = virt_text,
                        pos = ext.pos,
                        line = ext.to + total_lines,
                        col = ext.col,
                    })

                    if ext.hl_group == "line_idx" or ext.hl_group == "cursor_line_idx" then
                        table.insert(line_idx_exts, {
                            id = ext_id,
                            virt_text = virt_text,
                            pos = ext.pos,
                            line = ext.to + total_lines,
                            col = ext.col,
                            hl_group = ext.hl_group,
                        })
                    end
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

local function render_error(result, renderer, input)
    if result.path and result.path ~= vim.NIL then
        renderer.set_path(result.path, input.cwd)
    end

    renderer.insert_line("")
    renderer.insert_line(" \u{f421} " .. result.error, "error")
end

local function render_matched(result, renderer, input, count)
    renderer.set_path(result.path, input.cwd, count)

    local base_line = nil
    if result.line_idx and result.line_idx ~= vim.NIL then
        base_line = result.line_idx
        renderer.set_base_line_idx(base_line)
    end

    renderer.insert_line("")

    local count_before = 0
    for i = #result.before, 1, -1 do
        local line_idx = tostring(base_line - i)
        local item = result.before[i]
        if item and item ~= vim.NIL then
            renderer.insert_line(item, "context")
            renderer.set_line_idx(line_idx)
            count_before = count_before + 1
        end
    end

    if result.matched and result.matched ~= vim.NIL then
        renderer.set_offset(count_before + 3)
        for _, matched_line in ipairs(result.matched) do
            local line_idx = tostring(base_line)

            renderer.insert_line(matched_line, "matched")
            renderer.set_tick_around(0, string.len(matched_line), "matched_tick")
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

local function render_header(buf, results, input)
    local count = 0
    for _, result in ipairs(results) do
        if not result.error or result.error == vim.NIL then
            count = count + 1
        end
    end

    local matches_str = tostring(count)
    local matches_len = vim.fn.strwidth(matches_str)
    local errors_str = tostring(#results - count)
    local errors_len = vim.fn.strwidth(errors_str)
    local max_stat_len =math.max(matches_len, errors_len)

    if matches_len ~= max_stat_len then
        matches_str = string.rep(" ", max_stat_len - matches_len) .. matches_str
    end
    if errors_len ~= max_stat_len then
        errors_str = string.rep(" ", max_stat_len - errors_len) .. errors_str
    end

    local glob = table.concat(input.glob, ' ')
    if glob == "" then glob = "(default)" end

    local max_width = 13 + math.max(
        max_stat_len,
        vim.fn.strwidth(input.path),
        vim.fn.strwidth(input.pattern),
        vim.fn.strwidth(glob)
    )
    local rule = string.rep("─", max_width + 2)

    local header = {
        "\u{e370} Grep summary\u{e370}",
        "    \u{f422} #matches \u{f061} " .. matches_str,
        "    \u{f421} #errors  \u{f061} " .. errors_str,
        "   " .. rule,
        "    \u{f034e} Path     \u{f061} " .. input.path,
        "    \u{f0451} Pattern  \u{f061} " .. input.pattern,
        "    \u{eb01} Glob     \u{f061} " .. glob,
    }
    api.nvim_buf_set_lines(buf, 0, -1, false,  header)
    hl.set_extmark.header(buf, {
        start_line = 0,
        end_line = #header,
        start_col = 0,
        end_col = 0,
        hl_eol = true,
    })

    return #header, count
end
M.header = render_header

function M.results(buf, win, results, input)
    local win_width = api.nvim_win_get_width(win)

    api.nvim_set_option_value("modifiable", true, { buf = buf })

    hl.clear_extmarks(buf)
    states.results.clear()
    local total_lines, num_matches = render_header(buf, results, input)
    local count = 0
    for _, result in ipairs(results) do
        local renderer = create_result_renderer(buf)

        local sep = string.rep("─", win_width)
        renderer.insert_line("")
        renderer.set_virt_text(sep, "separator")

        if result.error and result.error ~= vim.NIL then
            render_error(result, renderer, input)
        else
            count = count + 1
            render_matched(result, renderer, input, { current = count, total = num_matches })
        end

        renderer.update_states(total_lines)
        total_lines = renderer.append_after(total_lines)
        renderer.update_line_idx_states()
    end

    api.nvim_set_option_value("modifiable", false, { buf = buf })
end

M.manipulate = {
    states = {
        is_empty = function(tab)
            local current_states = states.results.get(tab)
            if current_states and next(current_states.items) then return end
            return true
        end,
    },

    input = {
        move_to_next_eol = function(win, buf)
            local curr_pos = api.nvim_win_get_cursor(win)

            local next_row = curr_pos[1] + 1
            if next_row > input_height then
                next_row = 1
            end

            local next_lines = api.nvim_buf_get_lines(buf, next_row - 1, next_row, false)
            if #next_lines == 0 then return end
            local next_line = next_lines[1]

            api.nvim_win_set_cursor(win, { next_row, #next_line + 1 })
        end,

        get = function(buf)
            local lines = api.nvim_buf_get_lines(buf, 0, input_height, false)
            if #lines ~= input_height then return end

            local glob = {}
            for item in string.gmatch(lines[3], "%S+") do
                table.insert(glob, item)
            end

            return {
                path = lines[1],
                pattern = lines[2],
                glob = glob,
            }
        end,
    },

    results = {
        get_item_current = function(row)
            local current_states = states.results.get()
            if not current_states then return end

            for i = row - 1, 0, -1 do
                local on_row = current_states.items[i]
                if on_row then return on_row end
            end
        end,

        get_prev_item_line = function(row)
            local current_states = states.results.get()
            if not current_states then return end

            local found_current = false
            for i = row - 1, 0, -1 do
                local on_row = current_states.items[i]
                if on_row then
                    if found_current then
                        if on_row.offset then
                            return i + 1 + on_row.offset, on_row.line_idx_exts
                        else
                            return i + 2, on_row.line_idx_exts
                        end
                    else
                        found_current = true
                    end
                end
            end
        end,

        get_next_item_line = function(row)
            local current_states = states.results.get()
            if not current_states then return end

            for i = row, current_states.final_idx do
                local on_row = current_states.items[i]
                if on_row then
                    if on_row.offset then
                        return i + 1 + on_row.offset, on_row.line_idx_exts
                    else
                        return i + 2, on_row.line_idx_exts
                    end
                end
            end
        end,
    },
}

M.props = {
    input_geom = {
        width = function() return math.floor(api.nvim_get_option("columns") * 0.25) end,
        height = input_height + 1,
        col = function(dim)
            return math.floor((api.nvim_get_option("columns") - dim.companion.width) / 2)
        end,
        row = function(dim)
            return math.floor((api.nvim_get_option("lines") - dim.companion.height) / 2)
        end,
    },
}

return M
