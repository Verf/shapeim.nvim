---@class shapeim.complete
---@brief Built-in completion fallback for shapeim.nvim.
---
--- Uses Neovim's built-in completion mechanism (vim.fn.complete / 'completefunc')
--- when blink.cmp is not available.
---
--- Compatible with:
---   - Vanilla Neovim (CTRL-N / CTRL-P)
---   - mini.completion (uses completefunc)
---   - nvim-cmp (can source from completefunc)
---
--- Activated automatically by init.lua when blink.cmp is not detected.

local M = {}

local engine = require("shapeim.engine")

---Completion function for 'completefunc'.
---Called by Neovim when the user triggers completion (CTRL-N or auto-trigger).
---
---@param findstart number 1 to find the start column, 0 to find completions.
---@param base string The text to complete (for findstart=0).
---@return number|table start column, or list of completion words.
function M.completefunc(findstart, base)
  if not engine.state.enabled then
    return findstart == 1 and -3 or {}
  end

  if findstart == 1 then
    -- Find where the code starts (before cursor)
    local code = engine.extract_code_from_buffer()
    if code == "" then
      return -3 -- cancel completion
    end
    engine.state.current_code = code
    local col = vim.fn.col(".") - 1
    return col - #code
  end

  -- findstart == 0: return completion items
  local code = engine.state.current_code
  if code == "" then
    return {}
  end

  local candidates = engine.get_candidates(code)
  if not candidates then
    return {}
  end

  -- Convert to the format vim.fn.complete expects: array of {word, menu, ...}
  local items = {}
  for i, text in ipairs(candidates) do
    -- Format: { word = text, menu = tostring(i), dup = 1 }
    -- dup=1 allows same text to appear as separate entries (e.g., same char from different codes)
    table.insert(items, {
      word = text,
      menu = tostring(i),
      dup = 1,
    })
  end

  return items
end

---Enable the built-in completion fallback.
---Sets 'completefunc' and configures auto-trigger on [a-y] in Insert mode.
function M.enable()
  -- Only set up if we haven't already
  if M._enabled then
    return
  end
  M._enabled = true

  -- Set completefunc
  vim.bo.completefunc = "v:lua.require'shapeim.complete'.completefunc"

  -- Auto-trigger completion after typing [a-y]
  vim.api.nvim_create_autocmd("TextChangedI", {
    group = vim.api.nvim_create_augroup("ShapeimComplete", { clear = true }),
    callback = function()
      if not engine.state.enabled then
        return
      end
      local col = vim.fn.col(".") - 1
      if col <= 0 then
        return
      end
      local char = vim.fn.getline("."):sub(col, col)
      -- Check if the last typed character is a-y
      local byte = char:byte()
      if byte and byte >= 97 and byte <= 121 then
        -- Check if we have candidates
        local code = engine.extract_code_from_buffer()
        if code ~= "" then
          engine.state.current_code = code
          local candidates = engine.get_candidates(code)
          if candidates and #candidates > 0 then
            -- Trigger built-in completion popup
            -- col+1 because complete() uses 1-indexed column, and we want to show after the code
            vim.schedule(function()
              if vim.fn.pumvisible() == 0 then
                vim.fn.complete(col - #code + 1, candidates)
              end
            end)
          end
        end
      end
    end,
  })
end

---Disable the built-in completion fallback.
function M.disable()
  M._enabled = false
  vim.api.nvim_del_augroup_by_name("ShapeimComplete")
end

return M
