# Testing Strategy

## Unit Tests (plenary or standalone)
Run with: `nvim --headless -u NONE --cmd "set rtp+=." -l tests/<spec>.lua`

### compiler_spec.lua
Tests `shapeim.compiler`:
- Compile reference dictionary (wubi86.dict.yaml) → verifies entry count, unique codes
- File not found → error message
- Missing `...` separator → error message
- Default column order (code, text)
- Reversed column order (text, code)
- Output is valid mpack (decode succeeds)

### engine_spec.lua
Tests `shapeim.engine`:
- Initial state values
- `load_dict()` → success, dict populated
- `get_candidates("a")` → 4 candidates, correct order
- `get_candidates("zzzz")` → nil
- `get_candidates("aaaa")` → 1 candidate (unique)
- `get_candidates("aaaf")` → phrase candidates
- `extract_code_from_buffer` → function exists (integration tests handle actual buffer)
- `toggle()` → state transitions, status changes
- `enable()` / `disable()` → state changes, code reset
- `reset_code()` → clears current_code
- Status returns correct values

## Manual Test Checklist
Run in a Neovim instance with shapeim installed, dictionary compiled, and blink.cmp or built-in completion active.

### Setup & Toggle
- [ ] `require('shapeim').setup()` completes without errors
- [ ] `:ShapeimCompile` command exists
- [ ] `:checkhealth` or notification shows dictionary status
- [ ] Toggle key enables IM (status shows "中")
- [ ] Toggle key disables IM (status shows "EN")
- [ ] Statusline/lualine integration works

### Completion Menu
- [ ] Type `a` → completion menu shows 工, 戈, 弋, 七
- [ ] Type `aa` → menu updates to aa candidates
- [ ] Backspace → menu updates correctly
- [ ] Type `zzz` → no menu (invalid code cleared)

### Space Commit (Rule A)
- [ ] Type `a`, press Space → "工" inserted, "a" removed
- [ ] Type `aa`, press Space → first aa candidate inserted
- [ ] Space with no code → normal space inserted
- [ ] Space with IM disabled → normal space inserted

### 4-Key Unique Auto-Commit (Rule B)
- [ ] Find a code with exactly 1 candidate, type all 4 letters → auto-commits
- [ ] Confirm undo (press `u`) reverts the whole 4-char + commit as one step

### 5th-Key Auto-Top (Rule C)
- [ ] Type 4 codes that have candidates, then a 5th valid code char → first 4 committed, new code starts with 5th
- [ ] Type 4 codes that have NO candidates, then 5th char → 5th char cleared (Rule D)

### Invalid Clear (Rule D)
- [ ] Type `z` with IM enabled → char deleted, warning shown
- [ ] Type a valid prefix then an invalid char → invalid char deleted, code reverts

### Undo Integrity
- [ ] After a commit (Space, auto-commit, auto-top), press `u` → single undo step restores the code
- [ ] `.` (repeat) works after commits

### disable_on_insert_leave
- [ ] Default (`false`) → leaving Insert keeps IM state unchanged
- [ ] `true`, IM enabled → leaving Insert auto-disables IM (status shows "EN")
- [ ] `true`, IM already disabled → leaving Insert does nothing
- [ ] `true`, auto-disable triggers `User ShapeimToggle` (statusline updates)

### disable_on_insert_enter
- [ ] Default (`false`) → entering Insert keeps IM state unchanged
- [ ] `true`, IM enabled → entering Insert auto-disables IM (status shows "EN")
- [ ] `true`, IM already disabled → entering Insert does nothing
- [ ] `true`, auto-disable then manually toggle on → IM works normally during insert

### Both options enabled
- [ ] Enter Insert → auto-disabled → toggle on → type → leave Insert → auto-disabled again

### Interruption
- [ ] Type partial code, move cursor with arrow keys → code resets
- [ ] Type partial code, press Enter → code resets
- [ ] Type partial code, press Esc → code resets (InsertLeave)

### blink.cmp Integration
- [ ] When blink.cmp is present, source auto-registers
- [ ] Number keys select candidates by rank
- [ ] Tab/Enter navigate and accept candidates

### Built-in Fallback
- [ ] When blink.cmp is absent, built-in completion works
- [ ] `<C-n>` / `<C-p>` navigate candidates
- [ ] Compatible with mini.completion
