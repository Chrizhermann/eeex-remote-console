-- M_EEexRC.lua — EEex Remote Console
-- Engine auto-loads all M_*.lua from override alphabetically.
if not EEex_Active then return end

EEexRemote = {}

-- Config
local CMD_FILE = "override/eeex_remote_cmd.lua"
local RESULT_FILE = "override/eeex_remote_result.json"

-- JSON-encode a string (escape special chars)
local function _jsonStr(s)
    if s == nil then return "null" end
    s = tostring(s)
    s = s:gsub('\\', '\\\\')
    s = s:gsub('"', '\\"')
    s = s:gsub('\n', '\\n')
    s = s:gsub('\r', '\\r')
    s = s:gsub('\t', '\\t')
    return '"' .. s .. '"'
end

-- Write JSON result file
local function _writeResult(result)
    local out = io.open(RESULT_FILE, "w")
    if not out then
        _realPrint("EEexRemote: failed to write result file")
        return
    end

    out:write('{"status":' .. _jsonStr(result.status))
    if result.error then
        out:write(',"error":' .. _jsonStr(result.error))
    end
    if result.returnValue and result.returnValue ~= "nil" then
        out:write(',"returnValue":' .. _jsonStr(result.returnValue))
    end
    out:write(',"output":[')
    for i, line in ipairs(result.output or {}) do
        if i > 1 then out:write(',') end
        out:write(_jsonStr(line))
    end
    out:write(']}')
    out:close()
end

-- Capture print() output during command execution
local _capturedOutput = {}
local _realPrint = print

local function _capturePrint(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    _capturedOutput[#_capturedOutput + 1] = table.concat(parts, "\t")
end

-- Execute a command file and write results
local function _Execute()
    local f = io.open(CMD_FILE, "r")
    if not f then return end
    local code = f:read("*a")
    f:close()
    os.remove(CMD_FILE)

    -- Capture output
    _capturedOutput = {}
    print = _capturePrint

    local fn, loadErr = loadstring(code)
    local result
    if fn then
        local ok, ret = pcall(fn)
        if ok then
            result = {status = "ok", output = _capturedOutput, returnValue = tostring(ret)}
        else
            result = {status = "error", error = tostring(ret), output = _capturedOutput}
        end
    else
        result = {status = "parse_error", error = tostring(loadErr)}
    end

    print = _realPrint
    _writeResult(result)
end

-- Poll function — called every frame from .menu element
function EEexRemote.Poll()
    _Execute()
    return ""  -- empty string for text lua binding
end

-- Register the polling element after menus load
EEex_Menu_AddAfterMainFileLoadedListener(function()
    EEex_Menu_LoadFile("EEexRC")

    -- Hook WORLD_ACTIONBAR open to push our invisible polling menu alongside it
    local actionbarMenu = EEex_Menu_Find("WORLD_ACTIONBAR")
    local oldOnOpen = EEex_Menu_GetItemFunction(actionbarMenu.reference_onOpen)
    EEex_Menu_SetItemFunction(actionbarMenu.reference_onOpen, function()
        local result = oldOnOpen()
        Infinity_PushMenu("EEEX_REMOTE")
        return result
    end)
    local oldOnClose = EEex_Menu_GetItemFunction(actionbarMenu.reference_onClose)
    EEex_Menu_SetItemFunction(actionbarMenu.reference_onClose, function()
        Infinity_PopMenu("EEEX_REMOTE")
        return oldOnClose()
    end)
end)
