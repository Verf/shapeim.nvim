--- Unit tests for shapeim.compiler
--- Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/compiler_spec.lua

package.path = package.path .. ";lua/?.lua;lua/?/init.lua"

local compiler = require("shapeim.compiler")
local passed = 0
local failed = 0

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
  if val then
    passed = passed + 1
  else
    failed = failed + 1
    vim.api.nvim_err_writeln(string.format("FAIL: %s (expected truthy, got %s)", msg or "assertion", tostring(val)))
  end
end

local function assert_falsy(val, msg)
  if not val then
    passed = passed + 1
  else
    failed = failed + 1
    vim.api.nvim_err_writeln(string.format("FAIL: %s (expected falsy, got %s)", msg or "assertion", tostring(val)))
  end
end

vim.api.nvim_err_writeln("=== compiler_spec ===")

-- Test: compile the reference dictionary
do
  local input = "tests/wubi86.dict.yaml"
  local output = vim.fn.stdpath("data") .. "/shapeim_test_cache.mpack"
  vim.fn.mkdir(vim.fn.stdpath("data"), "p")
  local ok, msg = compiler.compile(input, output)
  assert_truthy(ok, "compile returns success")
  assert_truthy(msg:find("Compiled"), "compile message contains 'Compiled'")
  -- Verify output is valid
  local f_out = io.open(output, "rb")
  assert_truthy(f_out ~= nil, "output file exists")
  if f_out then
    local raw = f_out:read("*a")
    f_out:close()
    local dok, dict = pcall(vim.mpack.decode, raw)
    assert_truthy(dok, "output decodes as valid mpack")
    assert_truthy(dict ~= nil, "decoded dict is not nil")
    assert_truthy(vim.tbl_count(dict) > 1000, "dict has reasonable number of entries")
  end
end

-- Test: file not found
do
  local ok, msg = compiler.compile("/nonexistent/file.yaml", "/tmp/out.mpack")
  assert_falsy(ok, "compile returns failure for missing file")
  assert_truthy(msg:find("Cannot open"), "error message mentions 'Cannot open'")
end

-- Test: file without ... separator
do
  local tmp = os.tmpname() .. ".yaml"
  local f = io.open(tmp, "w")
  f:write("---\ncolumns:\n  - code\n  - text\n")
  f:close()
  local ok, msg = compiler.compile(tmp, os.tmpname() .. ".mpack")
  assert_falsy(ok, "compile fails without ... separator")
  assert_truthy(msg:find("..."), "error mentions missing ...")
  os.remove(tmp)
end

-- Test: columns default
do
  local tmp = os.tmpname() .. ".yaml"
  local f = io.open(tmp, "w")
  f:write("---\nname: test\n...\na\t工\n")
  f:close()
  local out = os.tmpname() .. ".mpack"
  local ok, msg = compiler.compile(tmp, out)
  assert_truthy(ok, "compile succeeds without explicit columns (uses default)")
  -- Verify output
  local f2 = io.open(out, "rb")
  local raw = f2:read("*a")
  f2:close()
  local dict = vim.mpack.decode(raw)
  assert_eq(#dict["a"], 1, "default columns: code='a' has 1 entry")
  assert_eq(dict["a"][1], "工", "default columns: text is '工'")
  os.remove(tmp)
  os.remove(out)
end

-- Test: columns with reversed order (text, code)
do
  local tmp = os.tmpname() .. ".yaml"
  local f = io.open(tmp, "w")
  f:write("---\ncolumns:\n  - text\n  - code\n...\n工\ta\n")
  f:close()
  local out = os.tmpname() .. ".mpack"
  local ok, msg = compiler.compile(tmp, out)
  assert_truthy(ok, "compile succeeds with reversed columns")
  local f2 = io.open(out, "rb")
  local raw = f2:read("*a")
  f2:close()
  local dict = vim.mpack.decode(raw)
  assert_eq(#dict["a"], 1, "reversed columns: code='a' has 1 entry")
  assert_eq(dict["a"][1], "工", "reversed columns: text is '工'")
  os.remove(tmp)
  os.remove(out)
end

-- Test: output is valid mpack
do
  local input = "tests/wubi86.dict.yaml"
  local output = vim.fn.stdpath("data") .. "/shapeim_test_cache.mpack"
  local f = io.open(output, "rb")
  local raw = f:read("*a")
  f:close()
  local ok, dict = pcall(vim.mpack.decode, raw)
  assert_truthy(ok, "output decodes as valid mpack")
  assert_truthy(dict ~= nil, "decoded dict is not nil")
  assert_eq(type(dict), "table", "decoded dict is a table")
end

-- Summary
vim.api.nvim_err_writeln(string.format("\n=== Results: %d passed, %d failed ===", passed, failed))
vim.cmd("qall!")
