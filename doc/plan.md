# `plan.md` - Neovim Native Shape-Based Input Method Engine

## 1. System Context & Objective
**Plugin Name:** `shapeim.nvim`
**Goal:** Implement a zero-dependency, ultra-fast Neovim input method (IM) plugin for shape-based (形码) Chinese input.
**Scope:** Full input (characters + phrases/words) based on dictionary content. Any shape-based dictionary is supported (Wubi, Cangjie, Zhengma, etc.).
**Constraints:**
- Must be written in pure Lua.
- Must integrate with completion UI: primary = `blink.cmp`, fallback = Neovim built-in completion (`vim.fn.complete()`), compatible with `mini.completion` and other `completefunc`-based plugins.
- Must preserve Neovim's native `undo` history (using `undojoin` where necessary).
- No external RPC/processes. State machine runs synchronously within Neovim.
- Punctuation: passthrough as-is (English punctuation). No full-width mapping in v1.

## 2. Core Architecture

### 2.1 Directory Structure
```
lua/shapeim/
  init.lua          -- setup(), toggle(), 入口
  compiler.lua      -- :ShapeimCompile, yaml->mpack
  engine.lua        -- state, get_candidates(), load_dict()
  source.lua        -- blink.cmp source
  complete.lua      -- vim.fn.complete() fallback
  keymap.lua        -- Space handler, TextChangedI autocommands
doc/
  architecture.md   -- Architecture overview, module graph, data flow
  modules/          -- Per-module docs (one per lua/shapeim/*.lua)
  api.md            -- Public API reference (setup, toggle, status)
  rules.md          -- Input rules state machine (Rule A/B/C/D)
  testing.md        -- Test strategy and manual test checklist
tests/
  wubi86.dict.yaml
  compiler_spec.lua
  engine_spec.lua
```
**Documentation Guidelines:**
- All docs in English, targeting both human maintainers and LLM agents.
- Each module doc must include: purpose, inputs/outputs, dependencies, edge cases.
- `rules.md` must describe the state machine as a formal decision tree (readable by an LLM for bug diagnosis).
- Docs are written incrementally — each implementation step produces its corresponding doc.

### 2.2 Module Responsibilities
The plugin consists of 5 isolated modules:
1. **`compiler.lua`**: Parses Rime `.dict.yaml` offline and serializes to `.mpack` for O(1) startup time.
2. **`engine.lua`**: The core state machine handling code length, validation, O(1) dictionary lookups, and candidate lookup (`engine.get_candidates(code) -> candidates[]`).
3. **`source.lua`**: The custom completion provider for `blink.cmp`.
4. **`complete.lua`**: Built-in completion fallback using `vim.fn.complete()` when blink.cmp is unavailable.
5. **`keymap.lua`**: Handles input interception (Space, Backspace, automatic 4-key commit) without breaking buffer state.

---

## 3. Data Structures & State Schema

### 3.1 Dictionary Structure (In-Memory)
```lua
-- Loaded from mpack. O(1) lookup.
-- Key: exact string code (e.g., "ggll")
-- Value: Array of candidates ordered by weight.
local Dict = {
    ["a"] = {"工", "戈"},
    ["aaaa"] = {"工"},
    -- ...
}
```

### 3.2 Global State (`engine.state`)
```lua
local state = {
    enabled = false,       -- IM toggle state
    current_code = "",     -- The alphabetical code currently being typed
    dict_loaded = false,   -- Lazy load flag
}
```

### 3.3 Code Accumulation Rules
- Only `[a-y]` (lowercase) accumulate into `current_code`.
- Any non-`[a-y]` action (cursor move, Enter, Esc, digit, symbol, `InsertLeave`) resets `current_code = ""` (interrupt accumulation).
- Backspace: naturally handled by buffer state; `current_code` syncs from buffer content on each `TextChangedI`.

---

## 4. Implementation Steps & LLM Directives

**Documentation Rule:** After completing each step, write/update the corresponding doc file in `doc/`:
- Step 1 → `doc/modules/compiler.md`, `doc/modules/engine.md` (loader portion)
- Step 2 → `doc/modules/source.md`, `doc/modules/complete.md`, `doc/api.md`
- Step 3 → `doc/modules/keymap.md`, `doc/rules.md`
- Step 4 → `doc/modules/init.md`, `doc/architecture.md` (finalize)

### Step 1: Dictionary Compiler & Loader (`compiler.lua` & `dict.lua`)
**Task:** Parse Rime YAML dict and implement high-performance caching.
- **Trigger:** Exposed as Neovim command `:ShapeimCompile {path/to/dict.yaml}`.
- **Input:** A standard Rime `*.dict.yaml` file (reference: `tests/wubi86.dict.yaml`).
- **Logic:**
  1. Read file line by line. Skip the YAML header (everything before `...`).
  2. Parse header `columns` field to determine column order (typically `[code, text]` or `[text, code]`).
  3. Parse data lines by splitting on tab. Map to Dict[code] = {candidate, ...}.
  4. Aggregation: keep ALL codes including short codes (方案A). Order by file line order (Rime's `sort: original`).
  5. Serialize using `vim.mpack.encode()` -> `vim.fn.stdpath('data') .. '/shapeim_cache.mpack'`.
- **Loader Directive:** Create `load_dict()`. Use `vim.mpack.decode()` to load into memory. **Crucial:** Only trigger `load_dict()` when the user toggles the IM on for the very first time (Lazy Loading).
- **Auto-compile:** If `setup({ dict_path = "..." })` is provided, on first load check if cache exists; if not, automatically compile from `dict_path` to the fixed cache location.

### Step 2: Completion Provider (`source.lua` + `complete.lua`)
**Task:** Provide candidate completion UI, preferring blink.cmp, falling back to built-in.

#### 2a: `blink.cmp` Source (`source.lua`)
- **Registration:** Auto-register via blink.cmp API in `setup()`. If blink.cmp is not installed, skip registration and use built-in fallback.
- **Directive:** Follow `blink.cmp` custom source API.
- **Trigger:** Trigger only when `engine.state.enabled == true` and cursor is adjacent to `[a-z]+`.
- **Candidate Selection:** Use blink.cmp's built-in accept keymaps. Map keys 1-9 to select candidates by index (matching shape-based IME convention). Space commits first candidate via custom handler (see Rule A).
- **Logic:**
  1. Extract the current word before the cursor (the code).
  2. Call `engine.get_candidates(code)`.
  3. Map the array of candidates to `blink.cmp` `CompletionItem`s.
  4. Set `filterText` to the exact code to ensure blink doesn't filter out Chinese characters.
  5. Assign sorting priority based on the array index (first item = highest priority).

#### 2b: Built-in Completion Fallback (`complete.lua`)
- **Trigger:** When blink.cmp is not detected at `setup()` time, activate built-in fallback.
- **Mechanism:** Set `'completefunc'` to a custom function that calls `engine.get_candidates(code)` and feeds results via `vim.fn.complete()`.
- **Trigger characters:** `[a-y]`. On each `TextChangedI`, if IM is enabled, call `vim.fn.complete(1, candidates)` to trigger the built-in popup menu.
- **Compatibility:** Works with `mini.completion`, `nvim-cmp` (via `completefunc`), and vanilla Neovim `CTRL-N`/`CTRL-P` navigation.

### Step 3: Core Input Logic & Buffer Manipulation (`keymap.lua` / `autocmd`)
**Task:** Handle the shape-based specific typing rules (4-key commit, space to commit, clear invalid).
**Architecture Decision:** Since `blink.cmp` requires text to actually exist in the buffer to trigger the menu, **we MUST let `a-z` characters enter the buffer natively**. We will control the text via `InsertCharPre`, `TextChangedI`, and specific keymaps.

#### Rule A: Space Commits Short Code (Space overriding)
- **Action:** `vim.keymap.set('i', '<Space>', custom_space_handler, {expr = true})`
- **Logic:**
  - If `!state.enabled` or cursor is not after a valid code: return `" "` (fallback to normal space).
  - If valid: Get `Dict[current_code][1]` (first candidate).
  - **Buffer Mutation:** Delete the `current_code` from the buffer, insert the Candidate.
  - **Undo Directive:** Before replacing the text, execute `vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-g>u", true, false, true), 'n', false)` to group the undo tree, OR use `vim.cmd('undojoin')` followed by `vim.api.nvim_buf_set_text()`.
  - Return `""` (swallow the space).

#### Rule B: 4-Key Unique Auto-Commit
- **Action:** Listen via `vim.api.nvim_create_autocmd("TextChangedI")`.
- **Logic:**
  - Read text before cursor. If `#code == 4`:
  - Check `Dict[code]`.
  - If it exists and `#Dict[code] == 1` (Unique candidate): Automatically replace the 4 letters in the buffer with the Chinese text.
  - *Edge case:* If `#Dict[code] > 1` (Collision), do nothing, wait for user to press Space or numeric keys via `blink.cmp` menu.

#### Rule C: 5th-Key Auto-Top (顶字上屏)
- **Action:** Inside the same `TextChangedI` callback. **Executed before Rule B.**
- **Logic:**
  - If `#code == 5`:
  - Extract `first4 = code:sub(1,4)` and `fifth = code:sub(5,5)`.
  - If `Dict[first4]` exists (has at least one candidate):
    - Auto-commit `Dict[first4][1]` (always first candidate; no uniqueness check).
    - Start new accumulation: `code = fifth`.
  - If `Dict[first4]` does not exist: clear the invalid 5th char (fall through to Rule D).
- **TextChangedI evaluation order:** Rule C → Rule B → Rule D.

#### Rule D: Invalid Code Auto-Clear (Like rime auto_clear)
- **Action:** Inside the same `TextChangedI` callback.
- **Logic:**
  - If the user types a character that makes `current_code` yield `nil` from `Dict` (e.g., typing 'z' when no z-prefix code exists):
  - Instantly delete that invalid character from the buffer.
  - Trigger a visual bell or `vim.api.nvim_echo` to notify user of invalid stroke.
- **Note:** `z` key is reserved for future reverse-lookup. In v1, `z` is treated as invalid and cleared.

### Step 4: Setup, Toggle & Persistence (`init.lua`)
**Task:** Provide `setup()`, toggle mechanism, and optional state persistence.

**Configuration (`setup()`):**
```lua
require('shapeim').setup({
    dict_path = nil,         -- Path to .dict.yaml. Auto-compile on first load if set.
    toggle_key = '<C-\\>',   -- Key binding for IM toggle
    persist_state = true,    -- Remember IM state across sessions
})
```

**Toggle:**
- Define `require('shapeim').toggle()`.
- Bind `toggle_key` in Insert and Normal modes.
- **Persistence:**
  - When `persist_state` is enabled, save `state.enabled` to a file in `vim.fn.stdpath('data')` on toggle.
  - On `VimEnter`, restore the saved state (lazy-load dict if needed).
- **Logic:**
  1. `state.enabled = not state.enabled`
  2. If toggled ON and `state.dict_loaded == false`, call `load_dict()`.
  3. If `persist_state`, write to state file.
  4. Echo state to user via `vim.notify` or `nvim_echo`.
  5. *Integration:* Provide an API to format lualine/statusline components (e.g., `require('shapeim').status() -> "中" | "EN"`).

---

## 5. Testing Strategy
- **Unit tests (plenary):** Pure logic — compiler parsing, `engine.get_candidates()`, code extraction, Dict structure validation.
- **Manual tests:** Interactive behavior — Space commit, 4-key auto-commit, 5th-key auto-top, invalid clear, undo integrity, blink.cmp integration, built-in completion fallback.
- **Test file:** `tests/wubi86.dict.yaml` serves as the reference dictionary for both unit and manual testing.

## 6. Critical Technical Constraints (For LLM to strictly follow)
1. **Performance:** Do not use heavy Regex (`vim.fn.match`) inside the typing loop (`TextChangedI` or `Space` handler). Use pure Lua string functions (`string.sub`, `string.byte`) for prefix and code extraction.
2. **Undo History Breaking:** The biggest risk in replacing buffer text programmatically is breaking the `.` (repeat) and `u` (undo) commands. Whenever replacing `[a-z]` with a Chinese character, ensure it is treated as a single atomic edit.
3. **Async / Scheduling:** Modifying the buffer inside `TextChangedI` might trigger Neovim lock errors (`E565: Not allowed to change text here`). Use `vim.schedule(function() ... end)` when applying `nvim_buf_set_text` within autocommands.
4. **Blink.cmp compatibility:** Ensure the `source.lua` returns a table that implements `get_trigger_characters`, `get_completions(context, callback)`, and `resolve(item, callback)` according to the latest `blink.cmp` source spec.
