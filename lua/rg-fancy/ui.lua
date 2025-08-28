local M = {}

local hl = require("rg-fancy.highlight")
local render = require("rg-fancy.render")

local myui = require("my-ui")

local ui = myui.declare_ui({
    geom = {
        companion = render.props.input_geom,
    },
})

local api = vim.api

local augroup = api.nvim_create_augroup("NaughieRgFancyUi", { clear = true })

local goto_item_line = function(fn_get_item)
    local win = ui.main.get_win()
    if not win then return end
    local buf = ui.main.get_buf()
    if not buf then return end

    local row, line_idx_ext = render.manipulate.results[fn_get_item]()
    if not row then return end
    local curr = render.manipulate.results.get_item_current()

    api.nvim_win_set_cursor(win, { row, 0 })

    if line_idx_ext then
        for _, ext in ipairs(line_idx_ext) do
            hl.update_extmark.focus_line_idx(buf, ext)
        end
    end

    if curr and curr.line_idx_exts then
        for _, ext in ipairs(curr.line_idx_exts) do
            hl.update_extmark[ext.hl_group](buf, ext)
        end
    end
end

M.results = {
    open = function(setup)
        if ui.main.get_win() then
            ui.main.focus()
        else
            ui.main.create_buf(function(buf)
                if setup.buf then setup.buf(buf) end
                api.nvim_set_option_value("modifiable", false, { buf = buf })
            end)

            ui.main.open_float(function(win)
                local local_ns = api.nvim_create_namespace("")
                api.nvim_win_set_hl_ns(win, local_ns)
                hl.define_matched_tick(local_ns)
            end)
        end
    end,

    close = function()
        if not myui.focus_on_last_active_ui() then myui.focus_on_last_active_win() end
        ui.main.close()
    end,

    focus = function()
        return ui.main.focus()
    end,

    set = function(new_results, input)
        local buf = ui.main.get_buf()
        if not buf then return end
        local win = ui.main.get_win()
        if not win then return end
        render.results(buf, win, new_results, input)
    end,

    open_item_current = function()
        local item = render.manipulate.results.get_item_current()
        if not item or not item.path then return end

        local path = vim.fn.fnameescape(item.path)

        myui.close_all()
        local ok = myui.open_file_into_last_active_win(path)
        if not ok then
            myui.open_file_into_current_win(path)
        end

        if item.base_line then
            api.nvim_win_set_cursor(0, { item.base_line, 0 })
        end
    end,
    goto_prev_item_line = function()
        return goto_item_line("get_prev_item_line")
    end,
    goto_next_item_line = function()
        return goto_item_line("get_next_item_line")
    end,
}

M.input = {
    open = function(setup)
        if ui.companion.get_win() then
            ui.companion.focus()
        else
            ui.companion.create_buf(function(buf)
                if setup.buf then setup.buf(buf) end

                vim.keymap.set("i", "<CR>", function()
                    local win = ui.companion.get_win()
                    if not win then return end
                    render.manipulate.input.move_to_next_eol(win, buf)
                end, { buffer = buf, silent = true })

                render.input(buf)
            end)
            ui.companion.open_float(function(win)
                local tab = api.nvim_get_current_tabpage()
                api.nvim_create_autocmd("WinClosed", {
                    group = augroup,
                    pattern = tostring(win),
                    callback = function()
                        ui.companion.delete_buf(tab)
                    end,
                })
            end)
        end
    end,

    close = function()
        ui.main.focus()
        ui.companion.close()
    end,

    clear = function()
        local buf = ui.companion.get_buf()
        if not buf then return end
        local win = ui.companion.get_win()
        if not win then return end

        api.nvim_win_set_cursor(win, { 1, 0 })
        render.input(buf)
    end,

    focus = function()
        return ui.companion.focus()
    end,

    get = function()
        local buf = ui.companion.get_buf()
        if not buf then return end
        return render.manipulate.input.get(buf)
    end,
}

M.update_ui_opts = function(opts)
    ui.update_opts(opts)
end

return M
