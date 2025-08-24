local M = {}

local ui = require("rg-fancy.ui")
local hl = require("rg-fancy.highlight")
local rpc = require("rg-fancy.rpc")

local default_opts = {
    keymaps = {
        global = {},
        results = {},
        input = {},
    },
}

local setups = {
    results = {
        buf = function(buf) end,
        win = function(win) end,
    },
    input = {
        buf = function(buf) end,
        win = function(win) end,
    },
}

local plugin_dir = ""

M.fn = {
    open_results = function()
        ui.results.open(setups.results)
    end,
    close_results = ui.results.close,
    focus_results = ui.results.focus,

    open_input = function()
        ui.input.open(setups.input)
    end,
    close_input = ui.input.close,
    focus_input = ui.input.focus,

    clear_input = ui.input.clear,

    open_and_ins_input = function()
        ui.input.open(setups.input)
        vim.cmd("startinsert!")
    end,

    grep = function()
        local input = ui.input.get()
        if not input then return end
        local cwd = vim.uv.cwd()
        local results = rpc.call.grep(cwd, input.path, input.pattern)
        if not results or results == vim.NIL then return end

        input.cwd = cwd
        ui.results.set(results, input)
    end,
}

local function define_keymaps_wrap(args, default_opts)
    local opts = vim.tbl_deep_extend("force", vim.deepcopy(default_opts), args[4] or {})

    local rhs = args[3]
    if type(rhs) == "string" and M.fn[rhs] then
        vim.keymap.set(args[1], args[2], M.fn[rhs], opts)
    else
        vim.keymap.set(args[1], args[2], rhs, opts)
    end
end

local function update_setup_functions(opts)
    if opts.keymaps then
        if opts.keymaps.results then
            setups.results.buf = function(buf)
                for _, args in ipairs(opts.keymaps.results) do
                    define_keymaps_wrap(args, { buffer = buf, silent = true })
                end
            end
        end

        if opts.keymaps.input then
            setups.input.buf = function(buf)
                for _, args in ipairs(opts.keymaps.input) do
                    define_keymaps_wrap(args, { buffer = buf, silent = true })
                end
            end
        end
    end
end

function M.setup(opts)
    plugin_dir = opts.plugin_dir

    if opts.keymaps then
        if opts.keymaps.global then
            for _, args in ipairs(opts.keymaps.global) do
                define_keymaps_wrap(args, { silent = true })
            end
        end
    end
    update_setup_functions(opts)

    if opts.border then
        ui.update_ui_opts({ background = opts.border })
    end

    hl.set_highlight_groups(opts.hl)

    rpc.register(plugin_dir, opts.rpc_ns)
end

return M
