---@class shapeim.engine
---@brief Core state machine, dictionary lookups, and path management.
---
--- Manages the global IM state, lazy dictionary loading,
--- and provides the O(1) candidate lookup via `get_candidates(code)`.
--- Also holds the canonical paths for the dictionary source and cache.
---
--- State fields:
---   enabled      (bool)   IM toggle state
---   current_code (string) Alphabetical code being accumulated
---   dict_loaded  (bool)   Whether dictionary is in memory
---   dict         (table)  Dict[code] = {candidate, ...}

local M = {}

-- Canonical paths, set by init.setup().
local dict_path = nil

---@class shapeim.EngineState
---@field enabled boolean
---@field current_code string
---@field dict_loaded boolean
---@field dict table|nil
---@field prefix_set table|nil Set of all valid code prefixes
---@field max_code_length number Max code length before auto-commit (default: 4)
---@field auto_select boolean Auto-commit first candidate at max length even with collisions
---@field auto_select_unique_candidate boolean Auto-commit when exactly 1 candidate at max length
---@field auto_clear boolean Clear invalid codes immediately

---Global engine state.
---@type shapeim.EngineState
M.state = {
  enabled = false,
  current_code = "",
  dict_loaded = false,
  dict = nil,
  prefix_set = nil,
  max_code_length = 4,
  auto_select = false,
  auto_select_unique_candidate = true,
  auto_clear = true,
}

---Get the dictionary source path.
---@return string|nil
function M.get_dict_path()
  return dict_path
end

---Set the dictionary source path. Called once by init.setup().
---@param path string
function M.set_dict_path(path)
  dict_path = vim.fn.expand(path)
end

---Get the compiled cache path.
---@return string
function M.get_cache_path()
  local dir = vim.fn.stdpath("data") .. "/shapeim"
  return dir .. "/cache.mpack"
end

---Ensure the mpack cache exists and is up-to-date.
---Compares dict_path mtime against cache mtime; recompiles if source is newer.
---@return boolean success
---@return string|nil error_message
function M.ensure_cache()
  if not dict_path then
    return false, "dict_path not set"
  end

  local cache_path = M.get_cache_path()
  local cache_dir = vim.fn.fnamemodify(cache_path, ":h")
  vim.fn.mkdir(cache_dir, "p")

  -- Check if recompile is needed
  if vim.fn.filereadable(cache_path) then
    local cache_mtime = vim.fn.getftime(cache_path)
    local dict_mtime = vim.fn.getftime(dict_path)
    if cache_mtime >= dict_mtime then
      return true -- Up to date
    end
  end

  -- Compile
  local compiler = require("shapeim.compiler")
  vim.notify("shapeim: compiling dictionary ...", vim.log.levels.INFO)
  local ok, msg = compiler.compile(dict_path, cache_path)
  if ok then
    vim.notify("shapeim: " .. msg, vim.log.levels.INFO)
    return true
  else
    vim.notify("shapeim: compile failed: " .. (msg or "unknown"), vim.log.levels.ERROR)
    return false, msg
  end
end

---Load the dictionary from the mpack cache into M.state.dict.
---Idempotent: does nothing if already loaded.
---@return boolean success
---@return string|nil error_message
function M.load_dict()
  if M.state.dict_loaded and M.state.dict then
    return true
  end

  local cache_path = M.get_cache_path()
  if not vim.fn.filereadable(cache_path) then
    return false, "Dictionary cache not found: " .. cache_path .. ". Run :ShapeimCompile first."
  end

  local f, err = io.open(cache_path, "rb")
  if not f then
    return false, "Cannot open cache: " .. (err or "unknown error")
  end
  local raw = f:read("*a")
  f:close()

  local ok, dict = pcall(vim.mpack.decode, raw)
  if not ok then
    return false, "Cache decode failed: " .. tostring(dict)
  end

  M.state.dict = dict
  M.state.dict_loaded = true

  -- Build prefix set: for every code in the dict, add all its prefixes.
  -- This allows partial codes (e.g., "vk" for "vkjs") to pass validation
  -- even if they don't have exact matches.
  local prefix_set = {}
  for code, _ in pairs(dict) do
    for i = 1, #code - 1 do
      local prefix = code:sub(1, i)
      prefix_set[prefix] = true
    end
  end
  M.state.prefix_set = prefix_set

  return true
end

---Reload the dictionary from cache. Resets loaded state so the next load
---reads the latest mpack file. Safe to call anytime.
function M.reload_dict()
  M.state.dict_loaded = false
  M.state.dict = nil
  M.state.prefix_set = nil
  return M.load_dict()
end

---Look up candidates for an exact code.
---@param code string The shape code (e.g., "ggll").
---@return string[]|nil candidates Ordered array of candidate texts, or nil if not found.
function M.get_candidates(code)
  if not M.state.dict then
    return nil
  end
  return M.state.dict[code]
end

---Extract the current shape code from the buffer text before the cursor.
---Reads the buffer directly; does not rely on M.state.current_code.
---
---@return string code The [a-y] substring immediately before cursor, or "".
function M.extract_code_from_buffer()
  local col = vim.fn.col(".") - 1
  if col <= 0 then
    return ""
  end
  local line = vim.fn.getline(".")
  -- Walk backwards from cursor position, collecting lowercase a-y chars
  local code = ""
  local pos = col
  while pos >= 1 do
    local byte = line:byte(pos)
    -- a=97, y=121 (skip z=122)
    if byte >= 97 and byte <= 121 then
      code = line:sub(pos, pos) .. code
      pos = pos - 1
    else
      break
    end
  end
  return code
end

---Check if a code is a valid prefix of any dictionary entry.
---Used to tolerate partial codes during typing (e.g., "vk" for "vkjs").
---@param code string
---@return boolean
function M.is_valid_prefix(code)
  if not M.state.prefix_set then
    return false
  end
  return M.state.prefix_set[code] == true
end
function M.reset_code()
  M.state.current_code = ""
end

---Enable the IM. Loads dictionary on first call.
---@return boolean ok
---@return string|nil err
function M.enable()
  if not M.state.dict_loaded then
    local ok, err = M.load_dict()
    if not ok then
      vim.notify("shapeim: " .. (err or "failed to load dictionary"), vim.log.levels.ERROR)
      return false, err
    end
  end
  M.state.enabled = true
  M.state.current_code = ""
  return true
end

---Disable the IM and reset state.
function M.disable()
  M.state.enabled = false
  M.state.current_code = ""
end

---Toggle the IM on/off.
---@return boolean new_state
function M.toggle()
  if M.state.enabled then
    M.disable()
  else
    M.enable()
  end
  return M.state.enabled
end

---Get a status string for statusline/lualine integration.
---@return string "中" when enabled, "EN" when disabled.
function M.status()
  return M.state.enabled and "中" or "EN"
end

---Apply behaviour configuration from setup().
---@param opts table Configuration options.
function M.configure(opts)
  if opts.max_code_length then
    M.state.max_code_length = opts.max_code_length
  end
  if opts.auto_select ~= nil then
    M.state.auto_select = opts.auto_select
  end
  if opts.auto_select_unique_candidate ~= nil then
    M.state.auto_select_unique_candidate = opts.auto_select_unique_candidate
  end
  if opts.auto_clear ~= nil then
    M.state.auto_clear = opts.auto_clear
  end
end

return M
