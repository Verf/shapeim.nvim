# engine.lua

## Purpose
Core state machine and dictionary lookups. Manages IM toggle state, lazy dictionary loading, and provides the O(1) candidate lookup used by all completion backends.

## Public API

### State
```lua
M.state = {
  enabled      = false,   -- IM toggle
  current_code = "",      -- Accumulated code being typed
  dict_loaded  = false,   -- Lazy-load flag
  dict         = nil,     -- Dict[code] = {candidate, ...}
  prefix_set   = nil,     -- { [prefix] = true } for all valid code prefixes
  max_code_length = 4,    -- Code length for auto-commit (4=Wubi, 5=Cangjie)
  auto_select  = false,   -- Auto-commit first at max length even with collisions
  auto_select_unique_candidate = true, -- Auto-commit when exactly 1 candidate
  auto_clear   = true,    -- Clear invalid codes immediately
}
```

### Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `M.load_dict()` | `ok, err` | Load mpack cache into `M.state.dict`. Idempotent. |
| `M.get_candidates(code)` | `string[] \| nil` | O(1) exact-code lookup. `nil` if dict not loaded or code not found. |
| `M.is_valid_prefix(code)` | `boolean` | True if `code` is a prefix of any dictionary entry. |
| `M.extract_code_from_buffer()` | `string` | Reads `[a-y]` chars immediately before cursor from buffer. |
| `M.reset_code()` | — | Sets `current_code = ""`. |
| `M.enable()` | `ok, err` | Enable IM; loads dict on first call. |
| `M.disable()` | — | Disable IM; resets code. |
| `M.toggle()` | `boolean` | Toggle IM; returns new state. |
| `M.status()` | `string` | Returns `"中"` or `"EN"` for statusline. |

### Code Extraction Logic (`extract_code_from_buffer`)
- Walks backwards from cursor position.
- Collects characters where byte ∈ [97, 121] (a-y).
- Stops at first non-[a-y] character, BOL, or cursor position 0.
- `z` (byte 122) is NOT collected — reserved for future reverse-lookup.

## Internal Details

### Dictionary Loading
- **Path:** `vim.fn.stdpath('data') .. '/shapeim_cache.mpack'`
- **Format:** Lua table serialized via `vim.mpack.encode()`.
- **Lazy:** Only called once, on first `enable()`. If toggle is never pressed, the dictionary is never loaded.
- **Prefix set:** After loading, a `prefix_set` is built containing all prefixes of all dictionary keys. This enables partial code tolerance (e.g., `"vk"` is tolerated even without exact matches because it's a prefix of `"vkjs"`).
- **Cache miss:** Returns error suggesting user run `:ShapeimCompile`.

### State Machine Context
The `current_code` field in `M.state` is _informational_. The authoritative code is always read from the buffer via `extract_code_from_buffer()`. This avoids desync between the internal state and what's actually in the buffer.

## Dependencies
- `vim.mpack` (built-in)
- `vim.fn.stdpath` (built-in)
- File I/O via `io.open`

## Edge Cases
| Case | Behavior |
|------|----------|
| `load_dict()` called, no cache file | Returns `false` with error message |
| `load_dict()` called, cache corrupted | Returns `false` with decode error |
| `get_candidates()` before dict loaded | Returns `nil` |
| `get_candidates("zzz")` — non-existent code | Returns `nil` |
| `extract_code_from_buffer()` at BOL | Returns `""` |
| `extract_code_from_buffer()` after Chinese char | Returns `""` (non-[a-y] breaks) |
| `extract_code_from_buffer()` after `z` | Returns `""` (z is excluded) |
| `enable()` with dict already loaded | Returns `true` immediately (no reload) |
