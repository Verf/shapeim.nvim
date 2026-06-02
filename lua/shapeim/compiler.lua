---@class shapeim.compiler
---@brief Parses Rime .dict.yaml and serializes to .mpack.
---
--- Invoked via `:ShapeimCompile` (no-args, uses dict_path from setup) or
--- programmatically via `require('shapeim.compiler').compile(input_path, output_path)`.
---
--- Dictionary Format (Rime .dict.yaml):
---   YAML header above `...`, then `code\ttext` lines.
---   Column order is declared in header `columns:` field.
---   Sort order is implicit from line order (sort: original).
---
--- Output: Lua table { [code] = {text, ...} } serialized via vim.mpack.

local M = {}

---Parse the YAML header to extract the `columns` order.
---Only parses the columns list; ignores all other YAML structure.
---@param lines string[] All lines of the file.
---@return string[] columns e.g., {"code", "text"}
local function parse_columns(lines)
  local in_header = false
  local in_columns = false
  local columns = nil
  for _, line in ipairs(lines) do
    if line == "---" then
      in_header = true
    elseif in_header then
      if line == "..." then
        break
      end
      -- Detect start of columns list
      if line:match("^columns:%s*$") then
        in_columns = true
        columns = {}
      elseif in_columns then
        local item = line:match("^%s+%-%s+(.+)$")
        if item then
          table.insert(columns, item)
        else
          -- Non-list-item line after columns: assumes columns ended
          in_columns = false
        end
      end
    end
  end
  return columns or { "code", "text" }
end

---Find the data start index (line after `...`).
---@param lines string[]
---@return number index of first data line, or 0 if not found.
local function find_data_start(lines)
  for i, line in ipairs(lines) do
    if line == "..." then
      return i + 1
    end
  end
  return 0
end

---Compile a Rime .dict.yaml file into an .mpack cache.
---
---The output format is a Lua table where:
---  key = exact code string (e.g., "ggll")
---  value = array of candidate texts, ordered by file line (weight descending).
---
---@param input_path string Path to .dict.yaml file.
---@param output_path string Path for output .mpack file.
---@return boolean success
---@return string|nil error_message
function M.compile(input_path, output_path)
  -- Read file
  local f, err = io.open(input_path, "r")
  if not f then
    return false, "Cannot open input file: " .. (err or "unknown error")
  end
  local raw = f:read("*a")
  f:close()

  -- Split into lines and handle Windows line endings
  local lines = {}
  for line in raw:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end

  -- Parse header to get column order
  local columns = parse_columns(lines)
  local code_idx, text_idx
  for i, col in ipairs(columns) do
    if col == "code" then
      code_idx = i
    elseif col == "text" then
      text_idx = i
    end
  end
  if not code_idx or not text_idx then
    return false, "Header 'columns' must include 'code' and 'text'"
  end

  -- Find where data starts
  local data_start = find_data_start(lines)
  if data_start == 0 then
    return false, "Data separator '...' not found in file"
  end

  -- Build dictionary: Dict[code] = {text1, text2, ...}
  local dict = {}
  local count = 0
  for i = data_start, #lines do
    local line = lines[i]
    if line == "" or line:sub(1, 1) == "#" then
      -- skip empty lines and comments
    else
      local tab_pos = line:find("\t", 1, true)
      if tab_pos then
        local code, text
        if code_idx == 1 then
          code = line:sub(1, tab_pos - 1)
          text = line:sub(tab_pos + 1)
        else
          text = line:sub(1, tab_pos - 1)
          code = line:sub(tab_pos + 1)
        end
        if code ~= "" and text ~= "" then
          if not dict[code] then
            dict[code] = {}
          end
          table.insert(dict[code], text)
          count = count + 1
        end
      end
    end
  end

  -- Serialize
  local ok, packed = pcall(vim.mpack.encode, dict)
  if not ok then
    return false, "mpack encoding failed: " .. tostring(packed)
  end

  local f_out, err_out = io.open(output_path, "wb")
  if not f_out then
    return false, "Cannot open output file: " .. (err_out or "unknown error")
  end
  f_out:write(packed)
  f_out:close()

  return true, ("Compiled %d entries (%d unique codes) to %s"):format(
    count,
    vim.tbl_count(dict),
    output_path
  )
end

---Neovim command handler for :ShapeimCompile.
---No arguments: reads dict_path and cache_path from engine.
---@param opts table Command options from nvim_create_user_command.
function M.command()
  local engine = require("shapeim.engine")
  local input_path = engine.get_dict_path()
  if not input_path then
    vim.notify("shapeim: dict_path not set. Call setup() first.", vim.log.levels.ERROR)
    return
  end

  local output_path = engine.get_cache_path()
  vim.notify("shapeim: compiling " .. input_path .. " ...", vim.log.levels.INFO)
  local ok, msg = M.compile(input_path, output_path)
  if ok then
    vim.notify("shapeim: " .. msg, vim.log.levels.INFO)
    engine.reload_dict()
    vim.notify("shapeim: dictionary reloaded", vim.log.levels.INFO)
  else
    vim.notify("shapeim: compile failed: " .. (msg or "unknown error"), vim.log.levels.ERROR)
  end
end

return M
