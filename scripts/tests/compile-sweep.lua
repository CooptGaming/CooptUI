-- Compile every Lua file passed on the command line, on the LuaJIT MQ2Lua actually is.
--
-- loadfile() compiles WITHOUT executing, so this is safe to run over modules that would
-- otherwise need the `mq` host. It catches two things nothing else in the pipeline does:
--
--   * syntax errors -- luacheck parses with its own grammar, and CI's Lua 5.4 accepts
--     constructs LuaJIT (5.1) rejects. This uses the real target.
--   * LuaJIT's COMPILE-TIME ceilings: 200 locals per function and 60 upvalues per closure.
--     app.lua already sits near both (see its comments), and neither luacheck nor Lua 5.4
--     reports them -- the failure mode is a module that simply refuses to load in game.
--
-- Usage (from the repo root):
--   luajit scripts/tests/compile-sweep.lua $(find lua -name '*.lua')
--   powershell: & $env:COOPT_LUAJIT scripts/tests/compile-sweep.lua (gci lua -r -filter *.lua).FullName
--
-- Note: `luajit -bl` is NOT an alternative here -- the vcpkg static build MQ ships reports
-- "jit.* modules not installed".

local bad = 0
for i = 1, #arg do
    local fn, err = loadfile(arg[i])
    if not fn then
        bad = bad + 1
        print('COMPILE FAIL: ' .. tostring(err))
    end
end

print(string.format('%d/%d files compile', #arg - bad, #arg))
os.exit(bad == 0 and 0 or 1)
