---@class shapeim.keymap
---@brief Core input handling: space commit, auto-commit, auto-top, invalid clear.
---
--- Architecture: a-z characters enter the buffer natively.
--- Rules are applied reactively via TextChangedI and a Space keymap.
---
--- Evaluation order (TextChangedI): Rule C → Rule B → Rule D
---
--- Rules:
---   A: Space commits first candidate of current code.
---   B: 4-code unique → auto-commit immediately.
---   C: 5th key → auto-commit first 4-code's first candidate, start new code.
---   D: Invalid code → clear last character, notify user.

local M = {}

local engine = require("shapeim.engine")

-- Augroup for shapeim autocommands
local augroup = vim.api.nvim_create_augroup("ShapeimKeymap", { clear = true })

---Replace the code text before the cursor with the given text.
---Uses atomic undo grouping so the replacement is a single undo step.
---Repositions cursor to the end of the inserted text.
---
---@param code_len number Length of the code to replace.
---@param text string Replacement text (Chinese character/phrase).
local function replace_code(code_len, text)
  local col = vim.fn.col(".") - 1
  if col < code_len then
    return
  end
  local line_num = vim.fn.line(".")
  local start_col = col - code_len

  -- Start undo sequence
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes("<C-g>u", true, false, true),
    "n",
    false
  )

  -- Replace the code characters with the text
  vim.api.nvim_buf_set_text(
    0,
    line_num - 1,
    start_col,
    line_num - 1,
    col,
    { text }
  )

  -- nvim_buf_set_text does not move the cursor; reposition to end of inserted text
  local new_col = start_col + #text
  pcall(vim.api.nvim_win_set_cursor, 0, { line_num, new_col })

  -- Reset engine code after replacement
  engine.reset_code()
end

---Handler for Space key when IM is enabled.
---Commits the first candidate of the current code.
---Returns a key sequence string (expr=true map): backspaces to delete code + candidate text.
---Uses <C-g>U for atomic undo grouping.
---@return string Key sequence to insert (space char for passthrough).
function M.space_handler()
  if not engine.state.enabled then
    return " "
  end

  local code = engine.extract_code_from_buffer()
  if code == "" then
    return " "
  end

  local candidates = engine.get_candidates(code)
  if not candidates or #candidates == 0 then
    return " "
  end

  -- Cannot modify buffer directly in an expr map (E565).
  -- Instead, return a key sequence: backspaces to delete the code + candidate text.
  -- Neovim processes the entire returned string as one input chunk, so undo groups naturally.
  local text = candidates[1]
  local keys = string.rep("<BS>", #code) .. text

  -- Reset engine state (deferred, after the keys are processed)
  vim.schedule(function()
    engine.reset_code()
  end)

  return keys
end

---TextChangedI callback: applies rules B, C, D.
function M.on_text_changed()
  if not engine.state.enabled then
    return
  end

  local code = engine.extract_code_from_buffer()

  -- If no code, check if the last char is non-a-y and reset
  if code == "" then
    engine.reset_code()
    return
  end

  -- Check if the last typed character is non-a-y (interruption)
  local col = vim.fn.col(".") - 1
  if col > 0 then
    local last_char = vim.fn.getline("."):sub(col, col)
    local byte = last_char:byte()
    -- Only a-y (97-121) are valid code characters
    if not byte or byte < 97 or byte > 121 then
      engine.reset_code()
      return
    end
  end

  engine.state.current_code = code
  local code_len = #code
  local max_len = engine.state.max_code_length

  -- Rule C: (max_code_length+1)-Key Auto-Top (must run before Rule B)
  if code_len == max_len + 1 then
    local first_n = code:sub(1, max_len)
    local last = code:sub(max_len + 1, max_len + 1)
    local first_n_cands = engine.get_candidates(first_n)
    if first_n_cands and #first_n_cands > 0 then
      -- Auto-commit first_n's first candidate, start new code with the last character
      vim.schedule(function()
        if not engine.state.enabled then return end
        local col2 = vim.fn.col(".") - 1
        if col2 < max_len + 1 then return end
        local line_num = vim.fn.line(".")
        local start_col = col2 - (max_len + 1)  -- back to start of all N+1 chars
        local end_col = col2 - 1                  -- exclude the last char
        vim.api.nvim_feedkeys(
          vim.api.nvim_replace_termcodes("<C-g>u", true, false, true),
          "n", false
        )
        vim.api.nvim_buf_set_text(
          0, line_num - 1, start_col, line_num - 1, end_col,
          { first_n_cands[1] }
        )
        -- Position cursor AFTER the last char so it becomes the new code start
        local new_col = start_col + #first_n_cands[1] + 1
        pcall(vim.api.nvim_win_set_cursor, 0, { line_num, new_col })
        engine.state.current_code = last
      end)
    else
      -- First N chars don't match any code: clear the extra char (Rule D)
      if not engine.state.auto_clear then return end
      vim.schedule(function()
        if not engine.state.enabled then return end
        local col3 = vim.fn.col(".") - 1
        if col3 < 1 then return end
        vim.api.nvim_buf_set_text(
          0, vim.fn.line(".") - 1, col3 - 1, vim.fn.line(".") - 1, col3,
          {}
        )
        vim.api.nvim_echo({{"shapeim: invalid stroke", "WarningMsg"}}, false, {})
        engine.state.current_code = code:sub(1, max_len)
      end)
    end
    return
  end

  -- Rule B: Max-Code-Length Auto-Commit
  if code_len == max_len then
    local candidates = engine.get_candidates(code)
    if candidates and #candidates > 0 then
      local should_commit = false
      if engine.state.auto_select then
        should_commit = true
      elseif engine.state.auto_select_unique_candidate and #candidates == 1 then
        should_commit = true
      end
      if should_commit then
        vim.schedule(function()
          if not engine.state.enabled then return end
          local cur_code = engine.extract_code_from_buffer()
          if cur_code == code then
            replace_code(max_len, candidates[1])
          end
        end)
      end
    end
    return
  end

  -- Rule D: Invalid Code Auto-Clear
  -- Check if current code has any candidates.
  -- For partial codes (len < max_len), also check if it's a valid prefix.
  local candidates = engine.get_candidates(code)
  if not candidates then
    -- Skip clearing if auto_clear is disabled
    if not engine.state.auto_clear then
      return
    end
    -- For codes shorter than max_len, tolerate if it's a valid prefix (user may be building up)
    if code_len < max_len and engine.is_valid_prefix(code) then
      return
    end
    -- Truly invalid: clear the last character
    vim.schedule(function()
      if not engine.state.enabled then return end
      local cur_code = engine.extract_code_from_buffer()
      if cur_code == code then
        local col2 = vim.fn.col(".") - 1
        if col2 < 1 then return end
        vim.api.nvim_buf_set_text(
          0, vim.fn.line(".") - 1, col2 - 1, vim.fn.line(".") - 1, col2,
          {}
        )
        vim.api.nvim_echo({{"shapeim: invalid stroke", "WarningMsg"}}, false, {})
        engine.state.current_code = code:sub(1, -2)
      end
    end)
    return
  end
end

---Setup all keymaps and autocommands for input handling.
function M.setup()
  -- Space keymap (Rule A)
  vim.keymap.set("i", "<Space>", M.space_handler, {
    expr = true,
    desc = "shapeim: space to commit",
  })

  -- TextChangedI autocommand (Rules B, C, D)
  vim.api.nvim_create_autocmd("TextChangedI", {
    group = augroup,
    callback = M.on_text_changed,
  })

  -- Reset code on InsertLeave
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = augroup,
    callback = function()
      engine.reset_code()
    end,
  })
end

return M
