---@class shapeim.source
---@brief blink.cmp completion source for shapeim.nvim.
---
--- Implements the blink.cmp custom source API.
--- Registered automatically by init.lua when blink.cmp is detected.
---
--- For manual registration, add to your blink.cmp config:
---   sources.providers.shapeim = {
---     name = 'shapeim',
---     module = 'shapeim.source',
---   }
---
--- API reference: https://cmp.saghen.dev/development/source-boilerplate

local source = {}

---Constructor required by blink.cmp's provider system.
---@param opts table Provider options from blink.cmp config.
---@return table source instance
function source.new(opts)
  local instance = setmetatable({}, { __index = source })
  instance.opts = opts or {}
  return instance
end

local engine = require("shapeim.engine")

---Characters that trigger this source.
---Only lowercase a-y (excluding z, reserved for future reverse-lookup).
---@return string[]
function source:get_trigger_characters()
  local chars = {}
  for i = 97, 121 do -- a through y
    table.insert(chars, string.char(i))
  end
  return chars
end

---Get completions for the current context.
---
---Extracts the current shape code from the buffer, looks up candidates,
---and returns them as blink.cmp CompletionItems.
---
---@param context blink.cmp.Context
---@param callback fun(response: blink.cmp.CompletionResponse|nil)
---@return fun():nil cancel Cancel function (nil = no cancellation needed).
function source:get_completions(context, callback)
  -- Only trigger when IM is enabled
  if not engine.state.enabled then
    callback(nil)
    return
  end

  -- Extract code from buffer at cursor position
  local code = engine.extract_code_from_buffer()
  if code == "" then
    callback(nil)
    return
  end

  -- Look up candidates
  local candidates = engine.get_candidates(code)
  if not candidates or #candidates == 0 then
    callback(nil)
    return
  end

  -- Sync engine state
  engine.state.current_code = code

  -- Build completion items
  -- Each candidate gets a textEdit that replaces the code with the Chinese text.
  -- filterText is set to the code so blink.cmp doesn't try to fuzzy match Chinese chars.
  local items = {}
  local bufnr = context.bufnr
  local cursor = context.cursor
  -- cursor is 0-indexed: { line, character }
  -- The code starts at cursor.character - #code and ends at cursor.character
  local start_col = cursor[2] - #code
  if start_col < 0 then
    start_col = 0
  end

  for i, text in ipairs(candidates) do
    local item = {
      label = text,
      filterText = code,
      kind = require("blink.cmp.types").CompletionItemKind.Text,
      textEdit = {
        newText = text,
        range = {
          start = { line = cursor[1], character = start_col },
          ["end"] = { line = cursor[1], character = cursor[2] },
        },
      },
    }
    table.insert(items, item)
  end

  callback({
    items = items,
    is_incomplete_forward = true,   -- Re-query on each new keystroke (code grows)
    is_incomplete_backward = true,  -- Re-query on backspace (code shrinks)
  })
end

return source
