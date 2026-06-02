# init.lua

## Purpose
Entry point for shapeim.nvim. Handles setup, configuration, auto-compile, toggle, state persistence, and completion provider registration.

## Public API

### `M.setup(opts)`
Main setup function. Must be called once in the user's Neovim config.

**Parameters:**
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dict_path` | `string\|nil` | `nil` | Path to `.dict.yaml`. Auto-compiles on first load if cache missing. |
| `toggle_key` | `string` | `"<C-\\>"` | Key binding for IM toggle (Insert and Normal modes). |
| `persist_state` | `boolean` | `true` | Remember IM toggle state across Neovim sessions. |
| `debug` | `boolean` | `false` | Show verbose info messages (toggle state, provider detection, compilation progress). |

**Actions performed by setup():**
1. Merges user opts with defaults.
2. Registers `:ShapeimCompile` command.
3. Calls `ensure_cache()` — auto-compiles if `dict_path` is set and cache missing.
4. Creates toggle keymap in Insert and Normal modes.
5. Registers completion provider (blink.cmp or built-in fallback).
6. Restores persisted state (via `vim.schedule` to avoid startup ordering issues).

### `M.toggle()`
Programmatic toggle. Same as pressing the toggle key.

### `M.status() -> string`
Returns `"中"` when IM is enabled, `"EN"` when disabled. Suitable for statusline/lualine integration.

```lua
-- lualine example
require('lualine').setup({
  sections = {
    lualine_x = { require('shapeim').status },
  },
})
```

## Internal Functions

### `ensure_cache() -> boolean`
Checks if `shapeim_cache.mpack` exists in `stdpath('data')`. If not and `dict_path` is configured, compiles the dictionary. Returns `false` if no dictionary is available (with a warning notification).

### `setup_completion()`
Detects blink.cmp availability (deferred via `vim.schedule()` to support lazy-loaded plugin managers):
- **blink.cmp available:** Registers `shapeim.source` as a blink.cmp provider with `score_offset = 100` (appears above other sources).
- **blink.cmp not available:** Activates `shapeim.complete` built-in fallback (sets `completefunc`, creates auto-trigger autocommand).

### State Persistence
- **File:** `stdpath('data')/shapeim_state.json`
- **Format:** `{"enabled": true}`
- **Save:** On each toggle.
- **Restore:** On `VimEnter` (via `vim.schedule` in `setup()`).
