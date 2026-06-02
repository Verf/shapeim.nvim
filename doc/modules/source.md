# source.lua

## Purpose
blink.cmp custom completion source for shapeim.nvim.

## API (blink.cmp Source Interface)

### `source.new(opts) -> table`
Constructor required by blink.cmp's provider system. Returns a new source instance with the given options.

### `source:get_trigger_characters() -> string[]`
Returns trigger characters `a` through `y` (lowercase). `z` is excluded (reserved for future reverse-lookup).

### `source:get_completions(context, callback)`
Standard blink.cmp completion handler.

**Input:**
- `context` — blink.cmp Context (contains `bufnr`, `cursor`, `trigger`).
- `callback` — function to call with `{ items, is_incomplete_forward, is_incomplete_backward }`.

**Logic:**
1. If IM is not enabled (`engine.state.enabled == false`), calls `callback(nil)` immediately.
2. Extracts current code via `engine.extract_code_from_buffer()`.
3. If code is empty, calls `callback(nil)`.
4. Looks up candidates via `engine.get_candidates(code)`.
5. If no candidates, calls `callback(nil)`.
6. Builds `CompletionItem[]` with `textEdit` that replaces the code range with the Chinese text.
7. Sets `filterText = code` so blink.cmp fuzzy-matches against the code, not Chinese characters.
8. Calls `callback({ items, is_incomplete_forward = true, is_incomplete_backward = true })` — both flags set to `true` to ensure blink.cmp re-queries on every keystroke (code growth) and backspace (code shrinkage).

**CompletionItem format:**
```lua
{
  label = "工",           -- Shown in menu
  filterText = "a",      -- Fuzzy matched against
  kind = Text,           -- blink.cmp item kind
  textEdit = {           -- Range to replace on accept
    newText = "工",
    range = {
      start = { line, start_col },
      ["end"] = { line, cursor_col },
    },
  },
}
```

## Registration
- **Auto:** `init.lua` detects blink.cmp (deferred via `vim.schedule()` for lazy-loaded plugin managers) and auto-registers.
- **Manual:** Add to user's blink.cmp config:
  ```lua
  sources.providers.shapeim = {
    name = "shapeim",
    module = "shapeim.source",
    score_offset = 100,
  }
  sources.default = { "shapeim", ... }
  ```

## Dependencies
- `shapeim.engine` — candidate lookup
- `blink.cmp` — runtime (detected at setup time)

## Edge Cases
| Case | Behavior |
|------|----------|
| IM disabled | `callback(nil)` — no completions |
| No code before cursor | `callback(nil)` |
| Code has no candidates | `callback(nil)` |
| Cursor at column 0 | `extract_code_from_buffer()` returns `""` |
| Code starts before line start (unlikely) | `start_col` clamped to 0 |
