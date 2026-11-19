-- Zero-dependency Lua 5.1 Busted-compatible test runner
-- Used locally when `luajit` is installed without `busted`; CI runs real `busted` on the exact same *_spec.lua files.

local pairs = pairs
local ipairs = ipairs
local type = type
local tostring = tostring
local pcall = pcall
local xpcall = xpcall
local table_insert = table.insert
local table_sort = table.sort
local table_concat = table.concat

local function deepEqual(a, b, seen)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	seen = seen or {}
	if seen[a] == b then
		return true
	end
	seen[a] = b
	for k, v in pairs(a) do
		if not deepEqual(v, b[k], seen) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function fmtVal(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	if type(v) == "table" then
		local parts = {}
		for k, val in pairs(v) do
			table_insert(parts, tostring(k) .. "=" .. tostring(val))
		end
		table_sort(parts)
		return "{" .. table_concat(parts, ", ") .. "}"
	end
	return tostring(v)
end

local function fail(msg)
	error(msg or "assertion failed", 3)
end

local assertObj = {}
setmetatable(assertObj, {
	__call = function(_, cond, msg)
		if not cond then
			fail(msg or ("Expected truthy value, got " .. fmtVal(cond)))
		end
		return cond
	end,
})

assertObj.are = {
	equal = function(expected, actual, msg)
		if expected ~= actual then
			fail(msg or ("Expected " .. fmtVal(expected) .. ", got " .. fmtVal(actual)))
		end
	end,
	same = function(expected, actual, msg)
		if not deepEqual(expected, actual) then
			fail(msg or ("Expected same table:\n  expected: " .. fmtVal(expected) .. "\n  actual:   " .. fmtVal(actual)))
		end
	end,
}
assertObj.are_not = {
	equal = function(expected, actual, msg)
		if expected == actual then
			fail(msg or ("Expected values not to be equal: " .. fmtVal(actual)))
		end
	end,
	same = function(expected, actual, msg)
		if deepEqual(expected, actual) then
			fail(msg or ("Expected tables not to be same: " .. fmtVal(actual)))
		end
	end,
}
assertObj.equal = assertObj.are.equal
assertObj.same = assertObj.are.same
assertObj.is_true = function(v, msg)
	if v ~= true then
		fail(msg or ("Expected true, got " .. fmtVal(v)))
	end
end
assertObj.is_false = function(v, msg)
	if v ~= false then
		fail(msg or ("Expected false, got " .. fmtVal(v)))
	end
end
assertObj.is_nil = function(v, msg)
	if v ~= nil then
		fail(msg or ("Expected nil, got " .. fmtVal(v)))
	end
end
assertObj.is_not_nil = function(v, msg)
	if v == nil then
		fail(msg or "Expected non-nil value, got nil")
	end
end
assertObj.is_truthy = function(v, msg)
	if not v then
		fail(msg or ("Expected truthy value, got " .. fmtVal(v)))
	end
end
assertObj.is_falsy = function(v, msg)
	if v then
		fail(msg or ("Expected falsy value, got " .. fmtVal(v)))
	end
end
assertObj.is_table = function(v, msg)
	if type(v) ~= "table" then
		fail(msg or ("Expected table, got " .. type(v)))
	end
end
assertObj.is_string = function(v, msg)
	if type(v) ~= "string" then
		fail(msg or ("Expected string, got " .. type(v)))
	end
end
assertObj.is_number = function(v, msg)
	if type(v) ~= "number" then
		fail(msg or ("Expected number, got " .. type(v)))
	end
end
assertObj.has_no = {
	errors = function(fn, msg)
		local ok, err = pcall(fn)
		if not ok then
			fail((msg and (msg .. ": ") or "") .. "Expected no errors, but got: " .. tostring(err))
		end
	end,
}
assertObj.has = {
	errors = function(fn, pattern)
		local ok, err = pcall(fn)
		if ok then
			fail("Expected function to raise an error, but it succeeded")
		end
		if pattern and not tostring(err):find(pattern, 1, true) then
			fail("Expected error matching " .. fmtVal(pattern) .. ", got: " .. tostring(err))
		end
	end,
}

_G.assert = assertObj

-- Suite tree
local rootSuite = { name = "root", children = {}, tests = {}, beforeEach = {}, afterEach = {} }
local suiteStack = { rootSuite }

local function currentSuite()
	return suiteStack[#suiteStack]
end

_G.describe = function(name, fn)
	local s = {
		name = name,
		parent = currentSuite(),
		children = {},
		tests = {},
		beforeEach = {},
		afterEach = {},
	}
	table_insert(currentSuite().children, s)
	table_insert(suiteStack, s)
	fn()
	suiteStack[#suiteStack] = nil
end
_G.context = _G.describe

_G.before_each = function(fn)
	table_insert(currentSuite().beforeEach, fn)
end

_G.after_each = function(fn)
	table_insert(currentSuite().afterEach, fn)
end

_G.it = function(name, fn)
	table_insert(currentSuite().tests, { name = name, fn = fn })
end

-- Collect spec files
local function listSpecs()
	local files = {}
	local p = io.popen('ls -1 tests/*_spec.lua 2>/dev/null')
	if p then
		for line in p:lines() do
			if line ~= "" then
				table_insert(files, line)
			end
		end
		p:close()
	end
	table_sort(files)
	return files
end

local specs = {}
if arg and #arg > 0 then
	for i = 1, #arg do
		table_insert(specs, arg[i])
	end
else
	specs = listSpecs()
end

if #specs == 0 then
	io.stderr:write("No *_spec.lua files found in tests/\n")
	os.exit(1)
end

for _, path in ipairs(specs) do
	local chunk, err = loadfile(path)
	if not chunk then
		io.stderr:write("Syntax/load error in " .. path .. ": " .. tostring(err) .. "\n")
		os.exit(1)
	end
	chunk()
end

local passed = 0
local failed = 0
local failures = {}

local function gatherHooks(suite, field)
	local chain = {}
	local cur = suite
	while cur do
		table_insert(chain, 1, cur)
		cur = cur.parent
	end
	local hooks = {}
	if field == "beforeEach" then
		for _, s in ipairs(chain) do
			for _, fn in ipairs(s.beforeEach) do
				table_insert(hooks, fn)
			end
		end
	else
		for i = #chain, 1, -1 do
			for _, fn in ipairs(chain[i].afterEach) do
				table_insert(hooks, fn)
			end
		end
	end
	return hooks
end

local function runSuite(suite, prefix)
	local label = prefix and (prefix .. " > " .. suite.name) or (suite.name ~= "root" and suite.name or nil)
	for _, t in ipairs(suite.tests) do
		local fullName = label and (label .. " :: " .. t.name) or t.name
		local befores = gatherHooks(suite, "beforeEach")
		local afters = gatherHooks(suite, "afterEach")
		local ok, err = xpcall(function()
			for _, fn in ipairs(befores) do
				fn()
			end
			t.fn()
		end, debug.traceback)
		for _, fn in ipairs(afters) do
			pcall(fn)
		end
		if ok then
			passed = passed + 1
			io.write("  [PASS] " .. fullName .. "\n")
		else
			failed = failed + 1
			io.write("  [FAIL] " .. fullName .. "\n")
			table_insert(failures, { name = fullName, err = err })
		end
	end
	for _, child in ipairs(suite.children) do
		runSuite(child, label)
	end
end

io.write(string.format("Running %d spec file(s)...\n", #specs))
runSuite(rootSuite, nil)
io.write(string.format("\nSummary: %d passed, %d failed\n", passed, failed))

if failed > 0 then
	io.write("\nFailures:\n")
	for i, f in ipairs(failures) do
		io.write(string.format("\n%d) %s\n%s\n", i, f.name, tostring(f.err)))
	end
	os.exit(1)
end
os.exit(0)
