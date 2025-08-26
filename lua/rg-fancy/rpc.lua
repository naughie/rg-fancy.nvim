local M = {}

local default_ns = "rg-fancy"
local default_context = 2

local router = require("nvim-router")

local rpc = { request = function() end }

local function to_context_length(context_length)
    if type(context_length) ~= "number" then return default_context end
    local n = math.floor(context_length)
    if n < 1 or n > 10 then return default_context end
    return n
end

function M.register(plugin_dir, new_ns, context_length)
    local info = {
        path = plugin_dir .. "/rg-fancy.rs",
        handler = "NeovimHandler" .. tostring(to_context_length(context_length)),
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
    grep = function(cwd, path, pattern, glob)
        return rpc.request("grep", cwd, path, pattern, glob)
    end,
}

return M
