# compiler.lua

## Purpose
Parses Rime `.dict.yaml` files and serializes the dictionary into an `.mpack` cache for O(1) runtime lookup.

## Entry Points
- **Programmatic:** `require('shapeim.compiler').compile(input_path, output_path)`
- **Neovim command:** `:ShapeimCompile {path/to/dict.yaml}` (outputs to `stdpath('data')/shapeim_cache.mpack`)

## Input Format (Rime .dict.yaml)

```yaml
---
name: wubi86
columns:
  - code
  - text
...
a	工
aa	式
aaaa	工
```

### Header Rules
- Everything between `---` and `...` is the YAML header.
- `columns:` list defines field order. Must contain `"code"` and `"text"`.
- `sort: original` means line order = weight order (no explicit weight column).

### Data Rules
- Each line: `code\ttext` (tab-separated).
- `code`: lowercase a-z, 1-4 characters.
- `text`: Chinese character(s), can be single char or phrase.
- Same `code` may appear multiple times with different `text` (all are kept).
- Same `text` may appear under multiple `code`s (valid — multiple encodings).
- Lines starting with `#` in data section are comments and ignored.

## Output Format

```lua
-- Serialized via vim.mpack.encode()
{
  ["a"]    = { "工", "戈", "弋", "七" },
  ["aa"]   = { "式", "戒", "工" },
  ["aaaa"] = { "工" },
  ...
}
```

- Keys are exact code strings.
- Values are arrays of candidate texts in file order (weight descending).
- No extra metadata stored (the mpack is a raw Lua table).

## Dependencies
- `vim.mpack` (Neovim built-in, no external libs).
- File I/O via `io.open`.

## Edge Cases
| Case | Behavior |
|------|----------|
| File not found | Returns `false, error_message` |
| Header missing `code`/`text` in columns | Returns error |
| Data line with < 2 tab-separated fields | Skipped |
| Empty code or text | Skipped |
| Duplicate entries (same code+text) | Both kept (no dedup) |
| mpack encoding failure | Returns error (unlikely) |
