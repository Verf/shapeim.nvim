---@class shapeim
---@brief Entry point for shapeim.nvim. Handles setup, auto-compile, toggle.
---
--- Usage:
---   require('shapeim').setup({
---     dict_path = "~/rime/wubi86.dict.yaml",
---     toggle_key = "<C-\\>",
---     persist_state = true,
---     debug = false,
---     max_code_length = 4,   -- 4 for Wubi, 5 for Cangjie
---     auto_select = false,
---     auto_select_unique_candidate = true,
---     auto_clear = true,
---   })

local M = {}

-- Module references (lazy-loaded)
local engine
local compiler

---@class shapeim.SetupOpts
---@field dict_path string|nil Path to .dict.yaml for auto-compile on first load.
---@field toggle_key string Key binding for IM toggle (default: "<C-\\>").
---@field persist_state boolean Remember IM state across sessions (default: true).
---@field debug boolean Show verbose info messages (default: false).
---@field max_code_length number Code length at which auto-commit triggers (default: 4, Wubi; use 5 for Cangjie).
---@field auto_select boolean Auto-commit first candidate at max_code_length even with collisions (default: false).
---@field auto_select_unique_candidate boolean Auto-commit when exactly 1 candidate at max_code_length (default: true).
---@field auto_clear boolean Clear invalid codes immediately (default: true).

---Default configuration.
local defaults = {
  dict_path = nil,
  toggle_key = "<C-\\>",
  persist_state = true,
  debug = false,
  max_code_length = 4,
  auto_select = false,
  auto_select_unique_candidate = true,
  auto_clear = true,
}

---Conditionally show an info-level notification (only when debug is true).
local function info(msg)
  if M._config and M._config.debug then
    vim.notify(msg, vim.log.levels.INFO)
  end
end

---Always show a warning notification.
local function warn(msg)
  vim.notify(msg, vim.log.levels.WARN)
end

---Always show an error notification.
local function err(msg)
  vim.notify(msg, vim.log.levels.ERROR)
end

-- State persistence file.
local function state_file_path()
  return vim.fn.stdpath("data") .. "/shapeim_state.json"
end

---Save the current enabled state to a JSON file.
local function persist_state()
  local ok, json = pcall(vim.json.encode, { enabled = engine.state.enabled })
  if not ok then
    return
  end
  local f, io_err = io.open(state_file_path(), "w")
  if not f then
    return
  end
  f:write(json)
  f:close()
end

---Restore the saved state from the JSON file.
local function restore_state()
  local path = state_file_path()
  if not vim.fn.filereadable(path) then
    return
  end
  local f, io_err = io.open(path, "r")
  if not f then
    return
  end
  local raw = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, raw)
  if ok and data and data.enabled then
    engine.enable()
  end
end

---Toggle the IM and persist state if configured.
local function toggle_im()
  local new_state = engine.toggle()
  -- Emit User event so downstream consumers (statusline, lualine, etc.)
  -- can react to state changes in real time.
  vim.api.nvim_exec_autocmds("User", { pattern = "ShapeimToggle" })
  if M._config.persist_state then
    persist_state()
  end
  info("shapeim: " .. engine.status())
end

---Ensure the cache exists. If dict_path is set and cache is missing, compile it.
local function ensure_cache()
  local cache_path = vim.fn.stdpath("data") .. "/shapeim_cache.mpack"
  if vim.fn.filereadable(cache_path) then
    return true
  end
  if M._config.dict_path then
    local expanded = vim.fn.expand(M._config.dict_path)
    if not vim.fn.filereadable(expanded) then
      err("shapeim: dict_path file not found: " .. expanded)
      return false
    end
    info("shapeim: compiling dictionary (one-time) ...")
    local ok, msg = compiler.compile(expanded, cache_path)
    if ok then
      info("shapeim: " .. msg)
      return true
    else
      err("shapeim: compile failed: " .. (msg or "unknown"))
      return false
    end
  end
  return false
end

---Create the toggle keymap in Insert and Normal modes.
local function setup_toggle_keymap()
  local key = M._config.toggle_key
  vim.keymap.set("i", key, toggle_im, { desc = "Toggle shapeim" })
  vim.keymap.set("n", key, toggle_im, { desc = "Toggle shapeim" })
end

---Setup the completion provider: blink.cmp or built-in fallback.
---Wrapped in vim.schedule so lazy-loaded blink.cmp is available when we check.
local function setup_completion()
  vim.schedule(function()
    -- Check if blink.cmp is available (re-check after schedule for lazy-loaded plugins)
    local has_blink, blink = pcall(require, "blink.cmp")
    if has_blink and blink then
      -- Register the blink.cmp source
      local registered = false
      pcall(function()
        local sources = require("blink.cmp.sources")
        if sources and sources.add_provider then
          sources.add_provider("shapeim", {
            name = "shapeim",
            module = "shapeim.source",
          })
          registered = true
        end
      end)
      -- Also try to add to default sources list
      pcall(function()
        local cfg = blink.get_config()
        if cfg and cfg.sources then
          local providers = cfg.sources.providers or {}
          providers.shapeim = {
            name = "shapeim",
            module = "shapeim.source",
            score_offset = 100,
            min_keyword_length = 1,
          }
          cfg.sources.providers = providers
          -- Add shapeim to default sources if not already present
          local def = cfg.sources.default or {}
          local found = false
          for _, s in ipairs(def) do
            if s == "shapeim" then found = true; break end
          end
          if not found then
            table.insert(def, 1, "shapeim")
            cfg.sources.default = def
          end
          registered = true
        end
      end)
      if registered then
        info("shapeim: registered as blink.cmp source")
      end
    else
      -- Fallback to built-in completion (vim.fn.complete / completefunc)
      local complete = require("shapeim.complete")
      complete.enable()
      info("shapeim: using built-in completion (mini.completion compatible)")
    end
  end)
end

---Setup shapeim.nvim.
---@param opts shapeim.SetupOpts|nil
function M.setup(opts)
  M._config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  -- Lazy-load modules
  engine = require("shapeim.engine")
  compiler = require("shapeim.compiler")

  -- Apply behaviour configuration to engine state
  engine.configure(M._config)

  -- Register :ShapeimCompile command
  vim.api.nvim_create_user_command("ShapeimCompile", compiler.command, {
    nargs = 1,
    complete = "file",
    desc = "Compile a Rime .dict.yaml to shapeim cache",
  })

  -- Ensure dictionary cache exists
  if not ensure_cache() then
    warn("shapeim: no dictionary found. Set dict_path in setup() or run :ShapeimCompile.")
  end

  -- Setup toggle keymap
  setup_toggle_keymap()

  -- Setup completion provider (deferred via vim.schedule for lazy-loaded blink.cmp)
  setup_completion()

  -- Setup input handling (keymaps, autocommands)
  local keymap = require("shapeim.keymap")
  keymap.setup()

  -- Restore persisted state
  if M._config.persist_state then
    vim.schedule(function()
      restore_state()
    end)
  end
end

---Toggle the IM on/off programmatically.
function M.toggle()
  toggle_im()
end

---Get status string for statusline/lualine.
---@return string "中" | "EN"
function M.status()
  return engine.status()
end

return M
