# complete.lua

## Purpose
Built-in completion fallback for shapeim.nvim. Uses Neovim's `'completefunc'` and `vim.fn.complete()` mechanism.

Activated automatically when blink.cmp is not detected at setup time.

## Compatibility
- Vanilla Neovim (`CTRL-N` / `CTRL-P` navigation)
- `mini.completion` (uses `completefunc`)
- `nvim-cmp` (can source from `completefunc`)
- Any plugin that leverages Neovim's built-in completion infrastructure

## Public API

### `M.completefunc(findstart, base) -> number | table`
Standard Neovim `'completefunc'` implementation.

- **findstart == 1:** Returns the column where completion starts (position of the first code character before cursor). Returns `-3` to cancel if IM is disabled or no code found.
- **findstart == 0:** Returns an array of `{ word, menu, dup }` tables for each candidate.

### `M.enable()`
Activates the fallback:
1. Sets `vim.bo.completefunc` to `M.completefunc`.
2. Creates `TextChangedI` autocommand that auto-triggers `vim.fn.complete()` after typing `[a-y]`.

### `M.disable()`
Removes the autocommand and disables the fallback.

## Auto-Trigger Logic
- On `TextChangedI`, checks if last typed character is `[a-y]`.
- If yes, calls `engine.extract_code_from_buffer()` to get the current code.
- If code has candidates (`engine.get_candidates()` returns non-nil), triggers `vim.fn.complete(startcol, candidates)`.
- Uses `vim.schedule()` to avoid `E565` (textlock) errors.

## Candidate Format
```lua
{ word = "工", menu = "1", dup = 1 }
```
- `dup = 1` allows the same Chinese character to appear as separate entries (e.g., same character accessible via different codes).

## Dependencies
- `shapeim.engine` — candidate lookup and state
- Neovim built-in completion API (`vim.fn.complete`, `completefunc`)

## Edge Cases
| Case | Behavior |
|------|----------|
| IM disabled | `completefunc` returns `-3` (cancel) |
| No code before cursor | No completion triggered |
| Code has no candidates | No completion triggered |
| `pumvisible()` already true | Skip trigger (avoid flicker) |
| `vim.schedule` callback after mode change | Guarded by `engine.state.enabled` check |
