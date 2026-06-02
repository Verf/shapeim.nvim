# shapeim.nvim

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A zero-dependency Neovim input method plugin for **shape-based (形码)** Chinese input.

Built with pure Lua, shapeim provides native shape-code typing inside Neovim —
code accumulation, candidate completion, auto-commit, and full undo
integrity — without external processes or RPC. Works with any shape-based
dictionary (Wubi, Cangjie, Zhengma, etc.) in Rime `.dict.yaml` format.

> 中文用户请参阅 [README_CN.md](./README_CN.md)

## Features

- 🚀 **Zero dependencies** — pure Lua, no external binaries
- ⚡ **Blazing fast** — O(1) dictionary lookup via mpack cache
- 📦 **Rime dictionary compatible** — use any Rime `.dict.yaml` file (Wubi, Cangjie, Zhengma, etc.)
- 🔌 **blink.cmp integration** — native completion menu with number key selection
- 🛟 **Built-in fallback** — works with vanilla Neovim, mini.completion, and nvim-cmp
- ⌨️ **Full shape-based input rules** — space commit, 4-key auto-commit, 5th-key auto-top (顶字上屏)
- 🔄 **Atomic undo** — every character commit is a single undo step
- 💾 **State persistence** — remembers IM toggle across sessions
- 📊 **Statusline support** — show `中`/`EN` in lualine or statusline

## Requirements

- Neovim ≥ 0.10
- A shape-based dictionary in Rime `.dict.yaml` format (e.g., [wubi86](https://github.com/rime/rime-wubi), [cangjie5](https://github.com/rime/rime-cangjie))
- [blink.cmp](https://github.com/Saghen/blink.cmp) (optional, for enhanced completion UI)

## Installation

### lazy.nvim

```lua
{
  "yourname/shapeim.nvim",
  opts = {
    dict_path = "~/rime/wubi86.dict.yaml",
  },
}
```

### packer.nvim

```lua
use {
  "yourname/shapeim.nvim",
  config = function()
    require("shapeim").setup({
      dict_path = "~/rime/wubi86.dict.yaml",
    })
  end,
}
```

### Manual

```lua
require("shapeim").setup({
  dict_path = "~/rime/wubi86.dict.yaml",
})
```

On first load, shapeim will **automatically compile** the dictionary from `dict_path`
into a fast mpack cache at `stdpath("data")/shapeim_cache.mpack`.

## Quick Start

1. Install the plugin with your preferred package manager.
2. Provide a dictionary path via `dict_path`.
3. Press `<C-\>` to toggle shape input (`中` status indicates it's on).
4. Start typing shape codes (lowercase `a`-`y`).
5. Press `<Space>` to commit the first candidate, or use number keys (`1`-`9`) with blink.cmp.

```
Toggle:  <C-\>          →  中 (IM on) / EN (IM off)
Type:    ggll           →  completion menu shows candidates
Commit:  <Space>        →  first candidate replaces the code
Auto:    4 unique keys  →  auto-committed immediately
Top:     type 5th key   →  first 4 committed, 5th starts new code
```

## Configuration

```lua
require("shapeim").setup({
  -- Path to Rime .dict.yaml file (auto-compiled on first load)
  dict_path = nil,

  -- Key to toggle IM on/off
  toggle_key = "<C-\\>",

  -- Remember IM state across Neovim sessions
  persist_state = true,

  -- Show verbose info messages (toggle, provider detection, compilation)
  debug = false,

  -- Code length for auto-commit (4 for Wubi, 5 for Cangjie)
  max_code_length = 4,

  -- Auto-commit first candidate at max length even with collisions
  auto_select = false,

  -- Auto-commit when exactly 1 candidate at max length
  auto_select_unique_candidate = true,

  -- Clear invalid codes immediately
  auto_clear = true,
})
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dict_path` | `string\|nil` | `nil` | Path to `.dict.yaml`. Auto-compiles on first load. |
| `toggle_key` | `string` | `"<C-\\>"` | Key binding for IM toggle. |
| `persist_state` | `boolean` | `true` | Save toggle state to disk, restore on startup. |
| `debug` | `boolean` | `false` | Show info-level notifications. |
| `max_code_length` | `number` | `4` | Code length at which auto-commit triggers. 4 for Wubi, 5 for Cangjie. |
| `auto_select` | `boolean` | `false` | Auto-commit first candidate at max length even with collisions. |
| `auto_select_unique_candidate` | `boolean` | `true` | Auto-commit when exactly 1 candidate at max length. |
| `auto_clear` | `boolean` | `true` | Clear invalid codes immediately. Set to `false` to allow manual correction. |

## Commands

| Command | Description |
|---------|-------------|
| `:ShapeimCompile {path}` | Compile a Rime `.dict.yaml` to the mpack cache. |

Use this if you didn't set `dict_path` in `setup()`, or want to recompile
after updating your dictionary.

## Input Rules

shapeim implements standard shape-based input behavior:

| Rule | Trigger | Behavior |
|------|---------|----------|
| **A: Space Commit** | Press `<Space>` | Commits the first candidate, replaces code with Chinese text |
| **B: 4-Key Auto-Commit** | Type 4th `[a-y]` key | If the code has exactly 1 candidate, auto-commits immediately |
| **C: 5th-Key Auto-Top** | Type 5th `[a-y]` key | Commits first candidate of the first 4 keys, 5th key starts new code |
| **D: Invalid Clear** | Type invalid code | Deletes the invalid character, shows warning |

Partial codes (fewer than 4 characters) that are valid prefixes of longer
dictionary entries are tolerated — no auto-clear. This allows gradual code
building (e.g., typing `vk` for the 4-code word `vkjs`).

Any non-`[a-y]` action (cursor move, `<Enter>`, `<Esc>`, digits) resets the
current code.

## Completion Backends

### blink.cmp (primary)

Detected automatically and registered as a source with `score_offset = 100`.
Number keys `1`-`9` select candidates by rank.

```lua
-- Customize in your blink.cmp config
sources.providers.shapeim = {
  name = "shapeim",
  module = "shapeim.source",
  score_offset = 100,
  min_keyword_length = 1,
}
```

### Built-in (fallback)

When blink.cmp is not installed, shapeim uses Neovim's built-in `completefunc`.
Navigate with `<C-n>` / `<C-p>`, accept with `<C-y>`.
Also compatible with [mini.completion](https://github.com/echasnovski/mini.completion)
and [nvim-cmp](https://github.com/hrsh7th/nvim-cmp).

## Statusline

```lua
-- lualine
require("lualine").setup({
  sections = {
    lualine_x = { require("shapeim").status },
  },
})

-- Manual statusline
vim.opt.statusline = "%{v:lua.require('shapeim').status()}"
```

Returns `中` when shape input is active, `EN` when disabled.

For real-time updates on `<C-\>` toggle, subscribe to the `User ShapeimToggle` event:

```lua
-- Add to your init.lua / autocmd config
vim.api.nvim_create_autocmd("User", {
  pattern = "ShapeimToggle",
  callback = function() vim.cmd.redrawstatus() end,
  desc = "Redraw statusline on shapeim toggle",
})
```

This is required for basic `vim.opt.statusline` (which only redraws on mode/event
changes). lualine users may not need this if their refresh interval is set, but
adding the autocmd guarantees instant updates.

## How It Works

```
Dictionary:  .dict.yaml  ──compiler──▶  .mpack cache (O(1) lookup)
                                          │
Typing:      a-y keys     ──buffer──▶  engine.get_candidates(code)
                                          │
Completion:  blink.cmp or completefunc ◀──┘
                                          │
Commit:      Space / auto  ──▶  nvim_buf_set_text (atomic undo)
```

1. **Compile:** `:ShapeimCompile` parses a Rime `.dict.yaml` and serializes it
   into an `.mpack` cache for O(1) startup.
2. **Type:** `a`-`y` characters enter the buffer natively so completion engines
   can detect the text before the cursor.
3. **Complete:** Candidates are looked up and displayed via blink.cmp or
   Neovim's built-in completion.
4. **Commit:** Space or auto-commit replaces the code characters with the
   Chinese text, using `<C-g>u` for atomic undo grouping.

## Documentation

- `:help shapeim` — Vim help (English)
- `:help shapeim-rules` — Input rules reference
- `:help shapeim-config` — Configuration options
- [plan.md](./doc/plan.md) — Design document (Chinese)
- [doc/](./doc/) — Architecture, API, module documentation

## Testing

```bash
# Run unit tests
nvim --headless -u NONE --cmd "set rtp+=." -l tests/compiler_spec.lua
nvim --headless -u NONE --cmd "set rtp+=." -l tests/engine_spec.lua
```

See [doc/testing.md](./doc/testing.md) for the manual test checklist.

## License

[MIT](./LICENSE)
