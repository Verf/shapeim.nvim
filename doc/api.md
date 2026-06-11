# Public API Reference

## `require('shapeim')`

### `setup(opts)`
Initialize shapeim.nvim. Call once in your Neovim config.

```lua
require('shapeim').setup({
  dict_path = "~/rime/wubi86.dict.yaml",  -- Path to .dict.yaml
  toggle_key = "<C-\\>",                   -- Key to toggle IM
  debug = false,                           -- Show verbose info messages
  max_code_length = 4,                     -- Code length for auto-commit (4=Wubi, 5=Cangjie)
  auto_select = false,                     -- Auto-commit first at max length even with collisions
  auto_select_unique_candidate = true,     -- Auto-commit when exactly 1 candidate at max length
  auto_clear = true,                       -- Clear invalid codes immediately
  disable_on_insert_leave = false,         -- Auto-disable IM when leaving insert mode
  disable_on_insert_enter = false,         -- Auto-disable IM when entering insert mode
})
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dict_path` | `string` | **required** | Path to Rime `.dict.yaml` file. Auto-compiles on startup; recompiles if source is newer than cache. |
| `toggle_key` | `string` | `"<C-\\>"` | Key binding for toggling the IM on/off. Bound in Insert and Normal modes. |
| `debug` | `boolean` | `false` | Show verbose info messages (toggle state, provider detection, compilation progress). |
| `max_code_length` | `number` | `4` | Code length at which auto-commit triggers. Set to 5 for Cangjie, 4 for Wubi. |
| `auto_select` | `boolean` | `false` | Auto-commit the first candidate when code reaches max_code_length, even with collisions. |
| `auto_select_unique_candidate` | `boolean` | `true` | Auto-commit when there is exactly one candidate at max_code_length. |
| `auto_clear` | `boolean` | `true` | Clear invalid codes immediately. Set to false to allow manual correction. |
| `disable_on_insert_leave` | `boolean` | `false` | Auto-disable IM when leaving insert mode. One-way: does not restore on re-entry. |
| `disable_on_insert_enter` | `boolean` | `false` | Auto-disable IM when entering insert mode. One-way: user can manually toggle on afterward. |

### `toggle()`
Toggle the IM on/off programmatically.

```lua
-- Equivalent to pressing the toggle key
require('shapeim').toggle()
```

### `status() -> string`
Get the current IM status for use in statusline/lualine components.

**Returns:**
- `"中"` when IM is enabled (shape input active)
- `"EN"` when IM is disabled (normal English input)

```lua
-- lualine example
require('lualine').setup({
  sections = {
    lualine_x = {
      require('shapeim').status,
    },
  },
})

-- Manual statusline
vim.opt.statusline = "%{v:lua.require('shapeim').status()}"
```

## `:ShapeimCompile`

Neovim command to recompile the dictionary from the `dict_path` set in `setup()`.

```
:ShapeimCompile
```

**Output:** `stdpath('data')/shapeim/cache.mpack`
**Note:** After compilation, the dictionary is automatically reloaded — no restart needed.
Use this when you update your dictionary during a session.

## Blink.cmp Integration

When blink.cmp is detected, shapeim auto-registers as a source. To customize:

```lua
-- In your blink.cmp config
sources = {
  providers = {
    shapeim = {
      name = "shapeim",
      module = "shapeim.source",
      score_offset = 100,   -- Show above other sources
      min_keyword_length = 1,
    },
  },
  default = { "shapeim", "lsp", "path", "buffer" },
}
```

**Keymaps:** Map keys `1`-`9` in blink.cmp's accept mappings to select candidates by number:

```lua
keymap = {
  preset = "default",
  ["<CR>"] = { "select_and_accept", "fallback" },
  ["1"] = { "select_and_accept", "fallback" },
  ["2"] = { "select_and_accept", "fallback" },
  -- ... etc
},
```

## Built-in Completion (fallback)
When blink.cmp is not detected, shapeim uses Neovim's built-in `completefunc`. Navigate candidates with `<C-n>` / `<C-p>` and accept with `<C-y>` (standard Neovim completion keys). Also compatible with `mini.completion` and `nvim-cmp`.
