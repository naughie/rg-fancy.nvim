# Rg-fancy

Rg-fancy is a Neovim plugin to use [ripgrep](https://github.com/BurntSushi/ripgrep) with a special UI.


# Requirements

- Rust (>= 1.85.0)

No [ripgrep] binary is required since we utilize the [grep crate](https://crates.io/crates/grep) directly.


# Install

After `nvim-router` detects that all of dependencies, which are specified in `opts.ns` of `nvim-router` itself, then it automatically runs `cargo build --release` and spawns a plugin-client process.

Once spawning you can grep-search.

## Lazy.nvim

### Config

```lua
{
    -- Dependencies
    { "naughie/glocal-states.nvim", lazy = true },
    { "naughie/my-ui.nvim", lazy = true },

    {
        "naughie/nvim-router",
        lazy = false,
        opts = function(plugin)
            return {
                plugin_dir = plugin.dir,
                ns = { "lazy-filer" },
            }
        end,
    },

    {
        "naughie/rg-fancy.nvim",
        lazy = false,
        opts = function(plugin)
            return {
                plugin_dir = plugin.dir,
                rpc_ns = "rg-fancy",

                -- Context length; that is, {context_length} lines before the match and
                -- {context_length} lines after the match are displayed.
                -- Default: 2, min: 1, max: 10
                context_length = 2,

                border = {
                    -- Highlight group for the border of floating windows.
                    -- Defaults to FloatBorder
                    hl_group = "FloatBorder",
                },
                -- Override highlight groups.
                -- You see all of the available highlights and their default values in the ./lua/rg-fancy/highlight.lua.
                hl = {
                    input_hint = { link = "Label" },
                    path = { link = "Operator" },
                    matched = { link = "Visual" },
                    header = { link = "Normal" },
                },

                -- { {mode}, {lhs}, {rhs}, {opts} } (see :h vim.keymap.set())
                -- We accept keys of require('rg-fancy').fn as {rhs}.
                keymaps = {
                    global = {
                        -- Open a grep-result window.
                        { 'n', '<C-g>', 'open_results' },
                    },

                    -- Keymaps on a grep-result window, opened by open_results
                    filer = {
                        -- Close the window.
                        { 'n', 'q', 'close_results' },

                        -- Open an grep-input window and enter the insert mode.
                        { 'n', 'i', 'open_and_ins_input' },

                        -- Move to the grep-input window if it already exists.
                        { 'n', '<C-j>', 'focus_input' },
                    },

                    -- Keymaps on a grep-input window, opened by open_input or open_and_ins_input
                    input = {
                        -- Close the window.
                        { 'n', 'q', 'close_input' },

                        -- Move to the grep-result window.
                        { 'n', '<C-k>', 'focus_results' },

                        -- Clear the buffer content.
                        { 'n', 'd', 'clear_input' },

                        -- Execute grep, and show the results in the grep-result window.
                        { 'n', '<CR>', 'grep' },
                    },
                },
            }
        end,
    },
}
```

