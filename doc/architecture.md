# Architecture Overview

## Plugin Identity
- **Name:** shapeim.nvim
- **Purpose:** Zero-dependency Neovim IM plugin for shape-based (形码) Chinese input (Wubi, Cangjie, Zhengma, etc.).
- **Language:** Pure Lua.

## Module Graph

```
┌──────────┐     ┌──────────┐
│ init.lua │────▶│engine.lua│
│ (setup)  │     │(state)   │
└────┬─────┘     └────┬─────┘
     │                │
     ▼                ▼
┌──────────┐     ┌──────────────┐     ┌──────────────┐
│compiler  │     │ source.lua   │     │ complete.lua │
│.lua      │     │ (blink.cmp)  │     │ (fallback)   │
└──────────┘     └──────────────┘     └──────────────┘
                       │                      │
                       └──────────┬───────────┘
                                  │
                                  ▼
                          ┌──────────────┐
                          │ keymap.lua   │
                          │ (input rules)│
                          └──────────────┘
```

## Data Flow

1. **Compile time:** `.dict.yaml` → `compiler.lua` → `.mpack` cache
2. **Setup:** `init.setup()` registers commands, keymaps, restores state
3. **Toggle ON:** `engine.enable()` → `engine.load_dict()` (lazy) → `state.enabled = true`
4. **Typing:** `keymap.lua` intercepts keys → `engine.get_candidates(code)` → completion UI
5. **Completion:** `source.lua` (blink.cmp) or `complete.lua` (built-in) renders candidates
6. **Commit:** Space handler or number key replaces code in buffer with Chinese text
7. **Toggle OFF:** `engine.disable()` → all interception stops → normal editing

## Key Design Decisions

- **Characters enter buffer natively** (`a-z`). This is required for blink.cmp/built-in completion to detect the prefix.
- **Code replacement uses atomic undo** (`<C-g>u` / `undojoin`) so undo/redo treats each character commit as one step.
- **O(1) dictionary lookup**: Dict is a flat Lua table keyed by exact code string, loaded from mpack.
- **Lazy loading**: Dictionary is only loaded on first IM toggle (not at startup).
- **Dual completion**: Primary = blink.cmp (rich UI), fallback = vim.fn.complete() (works with mini.completion, nvim-cmp, vanilla Neovim).
