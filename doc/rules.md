# Input Rules State Machine

This document describes the text input behavior when shapeim is enabled.

All rules operate on the current code (the `[a-y]` sequence before the cursor). The authoritative code is always read from the buffer via `extract_code_from_buffer()`; `engine.state.current_code` is a cache for convenience.

## Decision Tree (TextChangedI)

```
User types a character in Insert mode
  │
  ├─ IM disabled? ─── YES ──▶ Do nothing (passthrough)
  │
  └─ IM enabled
      │
      ├─ Char not in [a-y]? ─── YES ──▶ Reset current_code (interruption)
      │
      └─ Char in [a-y]
          │
          ├─ code_len == max_code_length + 1?
          │   │
          │   ├─ Dict[code[1:max]] exists? ─── YES ──▶ RULE C: Commit first_max[1], start new code with extra char
          │   │
          │   └─ Dict[code[1:max]] nil? ────▶ RULE D: Delete extra char, notify invalid
          │
          ├─ code_len == max_code_length?
          │   │
          │   ├─ auto_select OR (auto_select_unique_candidate AND #Dict[code]==1)? ─── YES ──▶ RULE B: Auto-commit
          │   │
          │   └─ Otherwise ───▶ Show candidates, wait for Space/Number
          │
          └─ Dict[code] == nil?
              │
              └─ YES ──▶ RULE D: Delete last char, notify invalid
```

## Rules Reference

### Rule A: Space Commit
- **Trigger:** User presses `<Space>` in Insert mode while IM is enabled.
- **Condition:** `current_code` is non-empty and `Dict[current_code]` exists.
- **Action:** Replace `current_code` in buffer with `Dict[current_code][1]` (first candidate). Swallow the space.
- **Fallback:** If code is empty or has no candidates, insert a normal space (`" "`).
- **Undo:** Replacement is a single atomic undo step (`<C-g>u`).

### Rule B: Max-Code-Length Auto-Commit
- **Trigger:** `TextChangedI` fires after the code reaches `max_code_length` (configurable, default 4).
- **Condition:** Controlled by `auto_select` and `auto_select_unique_candidate`:
  - `auto_select = true`: always commits first candidate at max length.
  - `auto_select_unique_candidate = true` (and `auto_select = false`): commits only when `#Dict[code] == 1`.
  - Both false: never auto-commits; user must use Space or number keys.
- **Undo:** Single atomic undo step.

### Rule C: Top-Character Auto-Commit (顶字上屏)
- **Trigger:** `TextChangedI` fires after code reaches `max_code_length + 1`.
- **Action:** Commit first candidate of the first `max_code_length` chars, start new code with the extra character.
- **Note:** No uniqueness check — always commits first candidate if the prefix has any match.

### Rule D: Invalid Code Auto-Clear
- **Trigger:** `TextChangedI` fires and `Dict[current_code] == nil`.
- **Prefix tolerance:** For codes shorter than `max_code_length`, if the code is a valid prefix of a longer entry, it is tolerated (user is building up).
- **Config:** Controlled by `auto_clear`. When `false`, invalid codes are never cleared.
- **Action (when cleared):** Delete the last typed character. Show warning.

## Interruption Rules
Any non-`[a-y]` action resets `current_code = ""`:
- Cursor movement (arrow keys, mouse)
- `<Enter>`, `<Esc>`
- Digits, symbols, punctuation
- `InsertLeave` event (switching to Normal mode)

## Notes
- `z` (byte 122) is excluded from `[a-y]` range. In shape-based schemes, `z` is reserved for pinyin reverse-lookup (future feature). Typing `z` with IM enabled triggers Rule D.
- Backspace is handled natively by the buffer. The code shortens, `TextChangedI` fires, and rules re-evaluate.
