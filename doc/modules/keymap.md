# keymap.lua

## Purpose
Core input handling for shapeim.nvim. Implements Rules A-D and the non-a-y interruption behavior.

## Architecture
`a-y` characters enter the buffer natively. This module reacts to buffer changes via:
- `TextChangedI` autocommand (Rules B, C, D, interruption detection)
- `<Space>` keymap with `expr = true` (Rule A)
- `InsertLeave` autocommand (code reset)

## Public API

### `M.space_handler() -> string`
Custom Space key handler (`expr = true` map). Returns a key sequence string instead of directly modifying the buffer (avoids E565 in expr maps).

Logic:
1. If IM disabled → return `" "` (normal space)
2. If no code before cursor → return `" "`
3. If code has no candidates → return `" "`
4. Otherwise → return `"<BS>" * code_len + candidate_text` (simulates backspaces + typing)

**Undo:** The returned key sequence is processed as one input chunk, so undo naturally groups it.

### `M.on_text_changed()`
`TextChangedI` callback. Applies rules in order C → B → D.

Uses `vim.schedule()` for all buffer modifications to avoid `E565` (textlock).

### `M.setup()`
Creates all autocommands and keymaps. Called by `init.lua` during setup.

## Internal Functions

### `replace_code(code_len, text)`
Atomically replaces `code_len` characters before the cursor with `text`. After replacement, repositions the cursor to the end of the inserted text via `nvim_win_set_cursor`.

**Used by:** Rule B (4-key auto-commit) — via `vim.schedule()` context (not expr map).

**Parameters:**
- `code_len` (number): Number of code characters to delete.
- `text` (string): Replacement text (Chinese character/phrase).

## Rule Implementation Details

### Rule A: Space Commit
- **Keymap:** `vim.keymap.set('i', '<Space>', handler, {expr = true})`
- **expr = true**: The handler returns a key sequence string. `"<BS>...<BS>text"` deletes the code then types the candidate.
- **Undo:** The returned key sequence is processed atomically by Neovim's input system, so undo groups naturally.

### Rules B/C/D: TextChangedI
- **Order enforced:** C → B → D via if-elseif chain.
- **Rule C (5th key):** Checks `#code == 5` first. If matched, does NOT fall through to B or D. Replaces the first 4 chars (not the last 4) with the candidate, then positions cursor after the 5th char so it becomes the start of a new code.
- **Rule B (4-key):** Checks `#code == 4` AND `#candidates == 1`. Uses `replace_code()` which repositions cursor after the inserted text.
- **Rule D (invalid):** Checks `get_candidates(code) == nil`. For codes shorter than 4, also checks `is_valid_prefix(code)` — if the code is a valid prefix of a longer dictionary entry, it is tolerated (user is building up to a full code).
- **Interruption check:** If last typed char is not `[a-y]`, resets code immediately (before any rule evaluation).

### vim.schedule() Usage
All buffer modifications in `TextChangedI` callbacks are wrapped in `vim.schedule()` to avoid Neovim lock errors. Before executing the scheduled modification:
- Checks `engine.state.enabled` (IM may have been toggled off)
- Re-reads the current code from the buffer (may have changed)
- Only proceeds if the code still matches what triggered the rule

### Cursor Positioning
After `nvim_buf_set_text` (which does not automatically move the cursor):
- `replace_code()` sets cursor to `start_col + #text` (end of inserted text)
- Rule C sets cursor to `start_col + #candidate + 1` (after the 5th char, so it starts the next code)

## Dependencies
- `shapeim.engine` — state, `extract_code_from_buffer()`, `get_candidates()`, `is_valid_prefix()`, `reset_code()`
- Neovim API — `nvim_buf_set_text`, `nvim_feedkeys`, `nvim_create_autocmd`, `nvim_echo`, `nvim_win_set_cursor`

## Edge Cases
| Case | Behavior |
|------|----------|
| Space pressed with cursor not after code | Returns `" "` (normal space) |
| Code cleared between trigger and vim.schedule | Guard check: `engine.state.enabled` |
| Cursor moved between trigger and vim.schedule | Guard check: re-reads code from buffer |
| Multiple rapid keystrokes | Each `TextChangedI` reads fresh code from buffer |
| `replace_code()` called with code_len > col | Returns early (no-op) |
| IM toggled off during scheduled callback | Guard check: `engine.state.enabled` |
| Partial code (len < 4) has no exact match but is a valid prefix | Tolerated (Rule D skips) |
