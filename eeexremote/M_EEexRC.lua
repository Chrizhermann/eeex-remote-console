-- M_EEexRC.lua — EEex Remote Console v0.2.0 (protocol 1.1)
-- Engine auto-loads all M_*.lua from override alphabetically.
-- Requires EEex 0.10+ with LuaJIT (io/os). Self-disables with a visible
-- reason otherwise — never spams per-frame errors.

if not EEex_Active then return end

-- Hot-reload guard: re-running this file via the console refreshes functions
-- but must not re-register listeners (menus keep their existing hooks).
local _isReload = (EEexRemote ~= nil) and (EEexRemote._registered == true)

EEexRemote = EEexRemote or {}
EEexRemote.PROTOCOL = "1.1"

-- ------------------------------------------------------------------ config
local CMD_FILE    = "override/eeex_remote_cmd.lua"
local RUN_FILE    = "override/eeex_remote_cmd.lua.run"
local RESULT_FILE = "override/eeex_remote_result.json"
local TMP_FILE    = "override/eeex_remote_result.json.tmp"
local READY_FILE  = "override/eeex_remote_ready.json"
local HOST_MENUS  = { "WORLD_ACTIONBAR", "START" }
local DEFAULT_WATCHDOG = 200000000 -- Lua instructions; ~1-2s of runaway loop
local MAX_DEPTH = 6                -- table serialization depth
local MAX_VALUE_JSON = 262144      -- max serialized bytes per return value

-- ------------------------------------------------------- capability probes
-- EEex has no version global; probe for what exists instead.
local compile  = loadstring or load
local register = EEex_Menu_AddAfterMainFileLoadedListener
              or EEex_Menu_AddMainFileLoadedListener -- 0.9.x name; 1.0 alias
local jitLib   = rawget(_G, "jit")
local _realPrint = print

EEexRemote.Disabled = nil
if not (io and os) then
    EEexRemote.Disabled = "EEex Remote Console disabled: Lua io/os libraries"
        .. " are missing. Install the EEex LuaJIT component"
        .. " (EEex v1.0.0: choose the Experimental tier)."
elseif not register then
    EEexRemote.Disabled = "EEex Remote Console disabled: EEex 0.10+ required."
end

-- ------------------------------------------------------------ JSON encoding
local JSON_ESCAPES = {
    ['\\'] = '\\\\', ['"'] = '\\"',
    ['\n'] = '\\n',  ['\r'] = '\\r', ['\t'] = '\\t',
    ['\b'] = '\\b',  ['\f'] = '\\f',
}

local function _jsonStr(s)
    if s == nil then return "null" end
    s = tostring(s)
    s = s:gsub('[%z\1-\31\\"]', function(c)
        return JSON_ESCAPES[c] or string.format('\\u%04X', string.byte(c))
    end)
    return '"' .. s .. '"'
end

-- Structured Lua -> JSON for return values. Cycle-safe, depth/size-limited.
local function _jsonValue(v, depth, seen)
    local t = type(v)
    if v == nil then return "null" end
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            return _jsonStr(tostring(v)) -- NaN/inf have no JSON form
        end
        return string.format("%.17g", v)
    end
    if t == "string" then return _jsonStr(v) end
    if t ~= "table" then return _jsonStr(tostring(v)) end -- function/userdata
    if seen[v] then return _jsonStr("<cycle>") end
    if depth >= MAX_DEPTH then return _jsonStr("<max depth>") end
    seen[v] = true
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    local parts = {}
    if n == #v then -- contiguous array (or empty table -> [])
        for i = 1, #v do
            parts[#parts + 1] = _jsonValue(v[i], depth + 1, seen)
        end
        seen[v] = nil
        return "[" .. table.concat(parts, ",") .. "]"
    end
    for k, val in pairs(v) do
        parts[#parts + 1] = _jsonStr(tostring(k)) .. ":"
            .. _jsonValue(val, depth + 1, seen)
    end
    seen[v] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

local function _jsonValueSafe(v)
    local ok, json = pcall(_jsonValue, v, 0, {})
    if not ok then
        return _jsonStr("<serialization error: " .. tostring(json) .. ">")
    end
    if #json > MAX_VALUE_JSON then
        return _jsonStr("<value too large: " .. #json .. " bytes>")
    end
    return json
end

-- ------------------------------------------------------------- result file
local function _writeResult(result)
    local out = io.open(TMP_FILE, "w")
    if not out then
        _realPrint("EEexRemote: failed to open " .. TMP_FILE)
        return
    end
    local parts = { '{"protocol":"' .. EEexRemote.PROTOCOL .. '"' }
    parts[#parts + 1] = ',"status":' .. _jsonStr(result.status)
    if result.id then
        parts[#parts + 1] = ',"id":' .. _jsonStr(result.id)
    end
    if result.error then
        parts[#parts + 1] = ',"error":' .. _jsonStr(result.error)
    end
    if result.traceback then
        parts[#parts + 1] = ',"traceback":' .. _jsonStr(result.traceback)
    end
    if result.durationMs then
        parts[#parts + 1] = ',"durationMs":' .. string.format("%d", result.durationMs)
    end
    if result.returnValue ~= nil then
        parts[#parts + 1] = ',"returnValue":' .. _jsonStr(result.returnValue)
    end
    if result.returnJson then
        parts[#parts + 1] = ',"returnValues":['
            .. table.concat(result.returnJson, ",") .. ']'
    end
    parts[#parts + 1] = ',"output":['
    for i, line in ipairs(result.output or {}) do
        if i > 1 then parts[#parts + 1] = ',' end
        parts[#parts + 1] = _jsonStr(line)
    end
    parts[#parts + 1] = ']}'
    out:write(table.concat(parts))
    out:close()
    -- Atomic publish: clients can never observe a partially written result.
    os.remove(RESULT_FILE) -- Windows rename fails if the target exists
    local ok, err = os.rename(TMP_FILE, RESULT_FILE)
    if not ok then
        _realPrint("EEexRemote: result rename failed: " .. tostring(err))
    end
end

-- ---------------------------------------------------------- output capture
local _capturedOutput = {}

local function _capturePrint(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    _capturedOutput[#_capturedOutput + 1] = table.concat(parts, "\t")
end

-- -------------------------------------------------------------- directives
-- Leading comment lines:  --@key  or  --@key=value  (nothing else before them)
local function _parseDirectives(code)
    local d, pos = {}, 1
    while true do
        local _, e, key, val = code:find("^%-%-@(%w+)=?([^\r\n]*)\r?\n?", pos)
        if not key then break end
        d[key] = (val ~= "" and val) or true
        if e >= #code then break end
        pos = e + 1
    end
    return d
end

-- ---------------------------------------------------------------- watchdog
local function _errHandler(msg)
    return { msg = tostring(msg), traceback = debug.traceback(tostring(msg), 2) }
end

local function _pack(...)
    return { n = select("#", ...), ... }
end

local function _runGuarded(fn, budget)
    if budget then
        -- Count hooks don't fire inside compiled LuaJIT traces; run the user
        -- chunk interpreted so the watchdog is reliable.
        if jitLib then jitLib.off() end
        debug.sethook(function()
            error("watchdog: exceeded " .. budget .. " Lua instructions"
                .. " (use --@nowatchdog for long scripts)", 2)
        end, "", budget)
    end
    local res = _pack(xpcall(fn, _errHandler))
    if budget then
        debug.sethook()
        if jitLib then jitLib.on() end
    end
    return res
end

-- --------------------------------------------------------------- execution
local function _Execute()
    -- Atomic claim: rename fails while a client still holds the file open
    -- (Windows sharing) and prevents double execution on internal errors.
    if not os.rename(CMD_FILE, RUN_FILE) then
        -- A stale claim file would block all future claims (rename-to-existing
        -- fails on Windows). RUN_FILE existing here is always stale: the normal
        -- path removes it before returning.
        local stale = io.open(RUN_FILE, "r")
        if stale then
            stale:close()
            os.remove(RUN_FILE)
        end
        return
    end
    local f = io.open(RUN_FILE, "r")
    if not f then os.remove(RUN_FILE); return end
    local code = f:read("*a")
    f:close()
    os.remove(RUN_FILE)

    local directives = _parseDirectives(code)
    local started = Infinity_GetClockTicks()

    _capturedOutput = {}
    print = _capturePrint

    local result
    local fn, loadErr = compile(code, "@eeex_remote_cmd.lua")
    if fn then
        local budget = nil
        if not directives.nowatchdog then
            budget = tonumber(directives.watchdog) or DEFAULT_WATCHDOG
        end
        local res = _runGuarded(fn, budget)
        if res[1] then
            local returnJson = {}
            for i = 2, res.n do
                returnJson[#returnJson + 1] = _jsonValueSafe(res[i])
            end
            result = { status = "ok", returnJson = returnJson }
            if res.n >= 2 and res[2] ~= nil then
                local okStr, str = pcall(tostring, res[2]) -- __tostring may throw
                result.returnValue = okStr and str or "<tostring error>"
            end
        else
            local err = res[2]
            if type(err) == "table" then
                result = { status = "error", error = err.msg,
                           traceback = err.traceback }
            else
                result = { status = "error", error = tostring(err) }
            end
        end
    else
        result = { status = "parse_error", error = tostring(loadErr) }
    end

    print = _realPrint
    result.output = _capturedOutput
    if type(directives.id) == "string" then result.id = directives.id end
    result.durationMs = Infinity_GetClockTicks() - started
    _writeResult(result)
end

-- ----------------------------------------------------------------- polling
function EEexRemote.Poll()
    if EEexRemote.Disabled then return "" end
    local ok, err = pcall(_Execute)
    if not ok then
        print = _realPrint          -- never leave print captured
        os.remove(RUN_FILE)         -- never leave a stale claim
        _realPrint("EEexRemote: internal error: " .. tostring(err))
    end
    return "" -- empty string for the text lua binding
end

-- --------------------------------------------------------- discoverability
-- Ground truth for the INSTALLED EEex version — what static docs can't give.
function EEexRemote.ListGlobals(pattern)
    local out = {}
    for name, value in pairs(_G) do
        if type(name) == "string"
                and (pattern == nil or name:find(pattern)) then
            local entry = { name = name, type = type(value) }
            if entry.type == "function" then
                local ok, info = pcall(debug.getinfo, value, "S")
                if ok and info and info.short_src
                        and info.short_src ~= "[C]" then
                    entry.source = info.short_src .. ":"
                        .. tostring(info.linedefined)
                end
            end
            out[#out + 1] = entry
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function EEexRemote.Info()
    return {
        protocol   = EEexRemote.PROTOCOL,
        luajit     = jitLib ~= nil,
        io         = io ~= nil,
        screens    = HOST_MENUS,
        disabled   = EEexRemote.Disabled,
        eeexActive = not not EEex_Active,
    }
end

-- --------------------------------------------------------------- ready file
local function _writeReady()
    local out = io.open(READY_FILE, "w")
    if not out then
        _realPrint("EEexRemote: failed to write " .. READY_FILE)
        return
    end
    out:write('{"protocol":"' .. EEexRemote.PROTOCOL .. '"'
        .. ',"luajit":' .. tostring(jitLib ~= nil)
        .. ',"screens":["' .. table.concat(HOST_MENUS, '","') .. '"]'
        .. ',"disabled":' .. (EEexRemote.Disabled
                              and _jsonStr(EEexRemote.Disabled) or "false")
        .. ',"timestamp":' .. _jsonStr(os.date("!%Y-%m-%dT%H:%M:%SZ"))
        .. '}')
    out:close()
end

-- ----------------------------------------------------------- host menu hooks
local _pushed = false

local function _hookHostMenu(menu)
    local oldOnOpen = EEex_Menu_GetItemFunction(menu.reference_onOpen)
    EEex_Menu_SetItemFunction(menu.reference_onOpen, function()
        local r
        if oldOnOpen then r = oldOnOpen() end
        if not _pushed then
            Infinity_PushMenu("EEEX_REMOTE")
            _pushed = true
        end
        return r
    end)
    local oldOnClose = EEex_Menu_GetItemFunction(menu.reference_onClose)
    EEex_Menu_SetItemFunction(menu.reference_onClose, function()
        if _pushed then
            Infinity_PopMenu("EEEX_REMOTE")
            _pushed = false
        end
        if oldOnClose then return oldOnClose() end
    end)
end

-- Fires after initial UI.MENU load AND after every F5 UI reload. A reload
-- rebuilds all menus from source (old wrappers are discarded), so re-hooking
-- here is correct and does not stack.
local function _onMenusLoaded()
    if EEexRemote.Disabled then
        _realPrint(EEexRemote.Disabled)
        if Infinity_DisplayString then
            Infinity_DisplayString(EEexRemote.Disabled)
        end
        return
    end
    _pushed = false
    os.remove(RUN_FILE) -- clear a stale claim from a previous crash
    local okLoad, errLoad = pcall(EEex_Menu_LoadFile, "EEexRC")
    if not okLoad then
        _realPrint("EEexRemote: menu load failed: " .. tostring(errLoad))
    end
    for _, name in ipairs(HOST_MENUS) do
        local m = EEex_Menu_Find(name)
        if m then
            local ok, err = pcall(_hookHostMenu, m)
            if not ok then
                _realPrint("EEexRemote: failed to hook " .. name .. ": "
                    .. tostring(err))
            end
        end
    end
    _writeReady()
end

if not _isReload then
    EEexRemote._registered = true
    if register then
        register(_onMenusLoaded)
    elseif EEexRemote.Disabled then
        _realPrint(EEexRemote.Disabled)
    end
end
