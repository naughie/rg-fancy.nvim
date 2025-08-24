local M = {}

local default_ns = "rg-fancy"

local router = require("nvim-router")

local rpc = { request = function() end }

function M.register(plugin_dir, new_ns)
    local info = {
        path = plugin_dir .. "/rg-fancy.rs",
        handler = "NeovimHandler",
    }

    if new_ns then
        info.ns = new_ns
    else
        info.ns = default_ns
    end

    local new_rpc = router.register(info)
    rpc.request = new_rpc.request
end

M.call = {
    grep = function(cwd, path, pattern)
        return rpc.request("grep", cwd, path, pattern)
    end,
}

return M
