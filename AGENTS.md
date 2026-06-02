# AGENTS.md

Guidance for AI coding agents working on shapeim.nvim.

## Project Identity

**shapeim.nvim** — zero-dependency Neovim input method plugin for shape-based (形码) Chinese input. Supports any Rime `.dict.yaml` dictionary (Wubi, Cangjie, Zhengma, etc.). Pure Lua, ~1100 lines across 6 modules.

## Architecture

```
lua/shapeim/
  init.lua        ── Entry point: setup(), toggle, persistence, completion wiring
  compiler.lua    ── Rime .dict.yaml → mpack cache (offline, :ShapeimCompile)
  engine.lua      ── State machine, dict loading, O(1) candidate lookup
  source.lua      ── blink.cmp completion source (primary UI)
  complete.lua    ── Built-in completion fallback (completefunc)
  keymap.lua      ── Input rules (Space commit, auto-commit, auto-top, invalid clear)
```

### Dependency Graph

```
init.lua ──▶ engine.lua (state, lookup)
         ├─▶ compiler.lua (compile command)
         ├─▶ source.lua OR complete.lua (completion, chosen at setup)
         └─▶ keymap.lua (input handling, reads engine.state)

source.lua ──▶ engine.lua
complete.lua ──▶ engine.lua
keymap.lua ──▶ engine.lua
```

### Data Flow

```
Rime .dict.yaml ──compiler──▶ .mpack cache (stdpath('data')/shapeim_cache.mpack)
                                       │
Typing [a-y] keys ──buffer──▶ engine.extract_code_from_buffer()
                                       │
                                       ▼
                              engine.get_candidates(code)
                                       │
                          ┌────────────┼────────────┐
                          ▼            ▼            ▼
                     source.lua   complete.lua   keymap.lua
                    (blink.cmp)  (fallback)    (auto-commit)
```

## Key Design Decisions

### Characters enter buffer natively
`a`-`y` letters are NOT intercepted. They appear in the Neovim buffer as typed. This is required for blink.cmp and built-in completion to detect the prefix before cursor. `TextChangedI` reacts to buffer changes to apply rules.

### O(1) dictionary
Dict is a flat Lua table: `Dict["ggll"] = {"不", ...}`. Loaded from mpack at first IM toggle (lazy). No prefix tree — a separate `prefix_set` table is built at load time for partial-code tolerance.

### Completion dual-backend
blink.cmp detected at setup time via `vim.schedule()` (deferred to support lazy-loaded plugin managers). Falls back to `vim.fn.complete()` / `completefunc` if blink is absent.

### Undo integrity
All buffer replacements use `<C-g>u` + `nvim_buf_set_text` for atomic undo grouping. Exception: Space handler (expr map) returns key sequences (`<BS>` * n + text) because expr maps can't call `nvim_buf_set_text`.

## Critical Gotchas

### 1. blink.cmp detection must be deferred
```lua
-- ❌ Wrong: fails with lazy.nvim (blink not loaded yet)
local has_blink, blink = pcall(require, "blink.cmp")

-- ✅ Correct:
vim.schedule(function()
  local has_blink, blink = pcall(require, "blink.cmp")
  ...
end)
```

### 2. expr=true keymaps cannot modify buffer
```lua
-- ❌ Wrong: E565 in expr map handler
function M.space_handler()
  vim.api.nvim_buf_set_text(...)  -- E565!
  return ""
end

-- ✅ Correct: return key sequence string
function M.space_handler()
  return string.rep("<BS>", #code) .. text  -- Neovim types these keys
end
```

### 3. nvim_buf_set_text does NOT move cursor
Always follow with `nvim_win_set_cursor`:
```lua
vim.api.nvim_buf_set_text(buf, row, start_col, row, end_col, {text})
pcall(vim.api.nvim_win_set_cursor, 0, {line, start_col + #text})
```

### 4. Rule C (top-character) range calculation
```lua
-- Cursor is after ALL N+1 characters. To replace first N:
local start_col = col2 - (max_len + 1)  -- NOT col2 - max_len
local end_col = col2 - 1                -- exclude the extra char
-- Cursor after: start_col + #candidate + 1 (after the extra char, so it
-- becomes the start of the next code and extract_code_from_buffer() sees it)
```

### 5. YAML header parsing must be targeted
Don't write a general YAML parser. Only extract the `columns` list. Nested structures (like `encoder:`) will fool a naive parser into adding their list items to `columns`.

```lua
-- ✅ Targeted approach:
local function parse_columns(lines)
  -- Only look for "columns:" at root level, collect its "- item" children
  -- Stop when next non-list-item line appears
end
```

### 6. LuaJIT compatibility
Avoid `goto`/`::label::` inside complex if-else blocks — LuaJIT can behave differently from PUC Lua. Use plain `if/else` or numeric `for` loops instead.

### 7. All buffer modifications in TextChangedI need vim.schedule()
```lua
function M.on_text_changed()
  ...
  vim.schedule(function()
    if not engine.state.enabled then return end  -- guard: IM may be off
    local cur_code = engine.extract_code_from_buffer()
    if cur_code ~= code then return end          -- guard: buffer changed
    ... -- safe to modify buffer
  end)
end
```

## Configuration Options (setup())

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dict_path` | string\|nil | nil | Path to .dict.yaml |
| `toggle_key` | string | `"<C-\\>"` | Toggle keymap |
| `persist_state` | boolean | true | Save state to disk |
| `debug` | boolean | false | Show info notifications |
| `max_code_length` | number | 4 | Code length for auto-commit (4=Wubi, 5=Cangjie) |
| `auto_select` | boolean | false | Auto-commit first at max length even with collisions |
| `auto_select_unique_candidate` | boolean | true | Auto-commit when exactly 1 candidate at max length |
| `auto_clear` | boolean | true | Clear invalid codes immediately |

## State Machine (engine.state)

```lua
engine.state = {
  enabled, current_code, dict_loaded, dict, prefix_set,
  max_code_length, auto_select, auto_select_unique_candidate, auto_clear,
}
```

All behaviour options live in `engine.state` so keymap.lua can read them without depending on init.lua. `engine.configure(opts)` is called by init's `setup()`.

## Input Rules (TextChangedI evaluation order)

1. **Interruption check** — non-`[a-y]` char → reset code
2. **Rule C** — `code_len == max_code_length + 1` → commit first N, start new code with extra char
3. **Rule B** — `code_len == max_code_length` → auto-commit based on `auto_select`/`auto_select_unique_candidate`
4. **Rule D** — `Dict[code] == nil` → clear if not valid prefix AND `auto_clear == true`

Space (Rule A) is separate: handled by an `expr=true` keymap on `<Space>`.

## Test Commands

```bash
# Unit tests (no Neovim config needed)
nvim --headless -u NONE --cmd "set rtp+=." -l tests/compiler_spec.lua
nvim --headless -u NONE --cmd "set rtp+=." -l tests/engine_spec.lua
```

Tests use a simple custom assertion framework (no plenary dependency). Currently 59 tests.

Manual test checklist: `doc/testing.md`

## Documentation Map

| File | Audience | Content |
|------|----------|---------|
| `README.md` | Users | Features, install, config, quick start (English) |
| `README_CN.md` | Users | Same, Chinese |
| `doc/shapeim.txt` | Users | `:help shapeim` Vim help |
| `doc/api.md` | Users | Public API reference |
| `doc/rules.md` | Users + devs | Input rules decision tree |
| `doc/architecture.md` | Devs | Module graph, data flow |
| `doc/modules/*.md` | Devs | Per-module specs (inputs/outputs/deps/edge cases) |
| `doc/testing.md` | Devs + QA | Test strategy and manual checklist |
| `doc/plan.md` | Devs | Original design document (Chinese) |
| `AGENTS.md` | AI agents | This file |

## File Naming & Conventions

- Lua source in `lua/shapeim/` (Neovim runtimepath convention)
- One module = one file, cohesive responsibility
- `---@class` / `---@field` LuaDoc annotations on public types
- Module-level functions use `M.` prefix; internal helpers are `local function`
- Prefer `vim.fn.col(".")` over `vim.api.nvim_win_get_cursor()` for cursor position (returns 1-indexed byte column)

## Adding a New Configuration Option

1. Add to `defaults` table in `init.lua`
2. Add `---@field` doc to `SetupOpts` class in `init.lua`
3. Add to `engine.state` defaults in `engine.lua`
4. Handle in `engine.configure()` in `engine.lua`
5. If it affects rules, update `keymap.lua`
6. Update: `README.md`, `README_CN.md`, `doc/shapeim.txt`, `doc/api.md`
7. Add tests to `engine_spec.lua`

## Supporting a New Dictionary Format

The compiler (`compiler.lua`) handles Rime `.dict.yaml` files. Key points:
- Header ends at `...` line
- `columns:` defines field order (typically `[code, text]` or `[text, code]`)
- Data lines are tab-separated
- `sort: original` means line order = weight
- Output is a flat `Dict[code] = {candidates...}` table serialized via `vim.mpack.encode()`
- `prefix_set` is built at load time by iterating all dict keys
