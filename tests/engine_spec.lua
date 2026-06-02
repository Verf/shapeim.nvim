--- Unit tests for shapeim.engine
--- Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/engine_spec.lua

package.path = package.path .. ";lua/?.lua;lua/?/init.lua"

local engine = require("shapeim.engine")
local compiler = require("shapeim.compiler")
local passed = 0
local failed = 0

-- Compile test dictionary to the proper cache location
local test_cache_dir = vim.fn.stdpath("data") .. "/shapeim"
vim.fn.mkdir(test_cache_dir, "p")
local test_cache_path = test_cache_dir .. "/cache.mpack"
compiler.compile("tests/wubi86.dict.yaml", test_cache_path)

local function assert_eq(actual, expected, msg)
  if actual == expected then
    passed = passed + 1
  else
    failed = failed + 1
    vim.api.nvim_err_writeln(string.format("FAIL: %s", msg or "assertion"))
    vim.api.nvim_err_writeln(string.format("  expected: %s", tostring(expected)))
    vim.api.nvim_err_writeln(string.format("  actual:   %s", tostring(actual)))
  end
end

local function assert_truthy(val, msg)
  if val then passed = passed + 1
  else failed = failed + 1; vim.api.nvim_err_writeln("FAIL: " .. (msg or "assertion")) end
end

vim.api.nvim_err_writeln("=== engine_spec ===")

-- Initial state
assert_eq(engine.state.enabled, false, "initial state: enabled is false")
assert_eq(engine.state.current_code, "", "initial state: current_code is empty")
assert_eq(engine.state.dict_loaded, false, "initial state: dict_loaded is false")
assert_eq(engine.state.dict, nil, "initial state: dict is nil")
assert_eq(engine.status(), "EN", "initial status is EN")

-- Default behaviour options
assert_eq(engine.state.max_code_length, 4, "default max_code_length is 4")
assert_eq(engine.state.auto_select, false, "default auto_select is false")
assert_eq(engine.state.auto_select_unique_candidate, true, "default auto_select_unique_candidate is true")
assert_eq(engine.state.auto_clear, true, "default auto_clear is true")

-- configure() updates state
engine.configure({ max_code_length = 5, auto_select = true, auto_select_unique_candidate = false, auto_clear = false })
assert_eq(engine.state.max_code_length, 5, "configure updates max_code_length to 5")
assert_eq(engine.state.auto_select, true, "configure updates auto_select to true")
assert_eq(engine.state.auto_select_unique_candidate, false, "configure updates auto_select_unique_candidate to false")
assert_eq(engine.state.auto_clear, false, "configure updates auto_clear to false")
-- Restore defaults for remaining tests
engine.configure({ max_code_length = 4, auto_select = false, auto_select_unique_candidate = true, auto_clear = true })

-- load_dict
do
  local ok, err = engine.load_dict()
  assert_truthy(ok, "load_dict succeeds with compiled cache")
  assert_truthy(engine.state.dict_loaded, "dict_loaded set to true after load")
  assert_truthy(engine.state.dict ~= nil, "dict is populated")
end

-- get_candidates
do
  local cands = engine.get_candidates("a")
  assert_truthy(cands ~= nil, "get_candidates('a') returns non-nil")
  assert_eq(#cands, 2, "get_candidates('a') returns 2 candidates")
  assert_eq(cands[1], "工", "first candidate for 'a' is 工")
  assert_eq(cands[2], "戈", "second candidate for 'a' is 戈")
end

-- get_candidates for non-existent code
do
  local cands = engine.get_candidates("zzzz")
  assert_eq(cands, nil, "get_candidates('zzzz') returns nil for non-existent")
end

-- get_candidates for unique 4-code
do
  local cands = engine.get_candidates("aaaa")
  assert_truthy(cands ~= nil, "get_candidates('aaaa') returns non-nil")
  assert_eq(#cands, 1, "get_candidates('aaaa') returns exactly 1 candidate")
end

-- get_candidates for multi-candidate code
do
  local cands = engine.get_candidates("fnhy")
  assert_truthy(cands ~= nil, "get_candidates('fnhy') returns non-nil")
  assert_truthy(#cands >= 1, "get_candidates('fnhy') has at least 1 candidate")
end

-- extract_code_from_buffer (requires buffer context)
-- This is tested in integration tests; unit test validates function exists
assert_eq(type(engine.extract_code_from_buffer), "function", "extract_code_from_buffer is a function")

-- toggle
do
  local s = engine.toggle()
  assert_eq(s, true, "toggle from disabled returns true (enabled)")
  assert_eq(engine.status(), "中", "status is 中 after enable")
end
do
  local s = engine.toggle()
  assert_eq(s, false, "toggle from enabled returns false (disabled)")
  assert_eq(engine.status(), "EN", "status is EN after disable")
  assert_eq(engine.state.current_code, "", "current_code reset on disable")
end

-- enable/disable
do
  local ok = engine.enable()
  assert_truthy(ok, "enable returns ok")
  engine.disable()
  assert_eq(engine.state.enabled, false, "disable sets enabled to false")
  assert_eq(engine.state.current_code, "", "disable resets current_code")
end

-- reset_code
do
  engine.state.current_code = "test"
  engine.reset_code()
  assert_eq(engine.state.current_code, "", "reset_code clears current_code")
end

-- Status after disable
assert_eq(engine.status(), "EN", "status is EN after disable")

-- Status after disable
assert_eq(engine.status(), "EN", "status is EN after disable")

-- Prefix set validation
assert_truthy(engine.is_valid_prefix("a"), "'a' is a valid prefix (exists in dict)")
assert_truthy(engine.is_valid_prefix("aa"), "'aa' is a valid prefix")
assert_truthy(engine.is_valid_prefix("aaa"), "'aaa' is a valid prefix")

-- get_cache_path
local cp = engine.get_cache_path()
assert_truthy(cp:find("shapeim"), "get_cache_path contains 'shapeim'")
assert_truthy(cp:find("cache%.mpack"), "get_cache_path contains 'cache.mpack'")

-- set_dict_path / get_dict_path
engine.set_dict_path("~/test.yaml")
local dp = engine.get_dict_path()
assert_truthy(dp ~= nil, "get_dict_path returns non-nil after set_dict_path")

-- ensure_cache (up-to-date check)
do
  local ok, err = engine.ensure_cache()
  assert_truthy(ok, "ensure_cache succeeds when cache is up to date")
end

-- reload_dict
do
  local ok, err = engine.reload_dict()
  assert_truthy(ok, "reload_dict succeeds")
  assert_truthy(engine.state.dict_loaded, "reload_dict sets dict_loaded")
end

-- Summary
vim.api.nvim_err_writeln(string.format("\n=== Results: %d passed, %d failed ===", passed, failed))
vim.cmd("qall!")
