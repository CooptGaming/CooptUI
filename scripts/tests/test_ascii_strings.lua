-- Every string the UI RENDERS must be plain ASCII.
--
-- Why this is a test and not a style note: MQ's ImGui does not render our source as UTF-8.
-- A middle dot (U+00B7, bytes C2 B7) comes out as "Â·" on the bar; an em dash (U+2014,
-- bytes E2 80 94) comes out as "â€”". Worse, an editor that reads such a file as Latin-1
-- and saves it back as UTF-8 DOUBLE-encodes it, and the damage compounds silently - which
-- is exactly what happened to views/augment_utility.lua and views/effects.lua before this
-- suite existed. Two FontAwesome glyph literals were mangled the same way and simply
-- stopped drawing.
--
-- So: ASCII in literals, and glyphs as \xNN escapes (which no editor can re-encode).
-- Comments are exempt - they are never drawn.
--
-- This is a source-text check, not a render check, so it runs standalone with no stub.

local repo = os.getenv('COOPT_REPO') or 'C:/Claude/CooptUI'

local pass, fail = 0, 0
local function check(name, cond, extra)
    if cond then
        pass = pass + 1
        print('PASS: ' .. name)
    else
        fail = fail + 1
        print('FAIL: ' .. name .. (extra and ('  -> ' .. tostring(extra)) or ''))
    end
end

-- Walk the shipped Lua trees. Uses the shell because LuaJIT has no directory API, and
-- keeps the list stable by sorting.
local function luaFiles()
    local out = {}
    local cmd = string.format('dir /b /s "%s\\lua\\*.lua" 2>nul', repo:gsub('/', '\\'))
    local p = io.popen(cmd)
    if not p then return out end
    for line in p:lines() do
        local f = line:gsub('\\', '/'):match('^%s*(.-)%s*$')
        -- Patcher_FreshInstall is a stale untracked SECOND COPY of the whole tree; it
        -- ships nothing and must never gate a build.
        if f ~= '' and not f:find('Patcher_FreshInstall', 1, true) then
            out[#out + 1] = f
        end
    end
    p:close()
    table.sort(out)
    return out
end

--- Strip comments so only code lines are inspected. Handles --[[ ]] blocks and -- lines.
local function codeLines(src)
    local out = {}
    local inblock = false
    local n = 0
    for line in (src .. '\n'):gmatch('([^\n]*)\n') do
        n = n + 1
        local st = line:match('^%s*(.-)%s*$')
        if inblock then
            if line:find(']]', 1, true) then inblock = false end
        elseif st:sub(1, 4) == '--[[' then
            if not line:find(']]', 1, true) then inblock = true end
        elseif st:sub(1, 2) ~= '--' then
            out[#out + 1] = { n = n, text = line }
        end
    end
    return out
end

--- Quoted literals on a line (single and double). Good enough for a lint: it does not
--- need to be a Lua parser, only to find the strings that reach the screen.
local function literals(line)
    local out = {}
    for s in line:gmatch('"([^"]*)"') do out[#out + 1] = s end
    for s in line:gmatch("'([^']*)'") do out[#out + 1] = s end
    return out
end

local files = luaFiles()
check('scan: found the lua tree', #files > 40, #files)

local offenders = {}
local scanned = 0
for _, path in ipairs(files) do
    local fh = io.open(path, 'rb')
    if fh then
        local src = fh:read('*a')
        fh:close()
        scanned = scanned + 1
        for _, cl in ipairs(codeLines(src)) do
            for _, lit in ipairs(literals(cl.text)) do
                for i = 1, #lit do
                    if lit:byte(i) > 127 then
                        offenders[#offenders + 1] = string.format('%s:%d  %s',
                            path:gsub('^.*/lua/', 'lua/'), cl.n, lit:sub(1, 60))
                        break
                    end
                end
            end
        end
    end
end

check('scan: read every file', scanned == #files, scanned .. '/' .. #files)
check('ascii: no rendered string carries a non-ASCII byte', #offenders == 0,
    '\n    ' .. table.concat(offenders, '\n    ', 1, math.min(#offenders, 25)))

-- The two glyphs that were mangled: prove they are escapes now, not raw bytes. A raw
-- literal here reads as three high bytes; an escape reads as the three the font wants.
-- The LINK glyph moved to components/window_header's shared GLYPHS table (windows pass
-- item 10) — one marker, one meaning, one definition — so the assertion follows it there
-- rather than being dropped. PIN stays local to augment_utility, its only caller.
do
    local function slurp(rel)
        local fh = io.open(repo .. rel, 'rb')
        local s = fh and fh:read('*a') or ''
        if fh then fh:close() end
        return s
    end
    local augUtil = slurp('/lua/itemui/views/augment_utility.lua')
    local header  = slurp('/lua/itemui/components/window_header.lua')
    check('glyphs: FontAwesome literals are \\xNN escapes',
        header:find('LINK    = "\\xEF\\x83\\x81"', 1, true) ~= nil
        and augUtil:find('GLYPH_PIN  = "\\xEF\\x82\\x8D"', 1, true) ~= nil)
end

print(string.format('\n%d passed, %d failed', pass, fail))
if fail > 0 then os.exit(1) end
