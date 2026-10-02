--!strict
-- UNC compatibility / environment test
--
-- This is an independently implemented compatibility test based on the
-- Unified Naming Convention API surface. It intentionally reports missing
-- globals and behavioural failures separately.
--
-- Run this in a Roblox/Luau environment that exposes executor APIs.

local passed = 0
local failed = 0
local missing = 0
local results = {}

local function resolve(path: string): any
    local value = getfenv and getfenv(0) or _G
    for part in string.gmatch(path, "[^%.]+") do
        if value == nil then
            return nil
        end
        value = value[part]
    end
    return value
end

local function record(name: string, ok: boolean, detail: string?)
    table.insert(results, {
        name = name,
        ok = ok,
        detail = detail,
    })
    if ok then
        passed += 1
        print("✅ " .. name .. (detail and (" • " .. detail) or ""))
    else
        failed += 1
        warn("⛔ " .. name .. (detail and (": " .. detail) or ""))
    end
end

local function test(name: string, callback: () -> any)
    local ok, result = pcall(callback)
    if ok then
        record(name, true, type(result) == "string" and result or nil)
    else
        record(name, false, tostring(result))
    end
end

local function exists(name: string)
    local value = resolve(name)
    if value == nil then
        missing += 1
        warn("⚠️ " .. name .. " is missing")
        return false
    end
    return true
end

local function testExists(name: string)
    record(name, exists(name))
end

local function assertType(value: any, expected: string, label: string)
    assert(type(value) == expected, label .. " must be " .. expected .. ", got " .. type(value))
end

print("")
print("UNC Compatibility Test")
print("=======================")
print("This checks the documented UNC-style API surface and selected behaviour.")
print("Missing APIs are reported separately from behavioural failures.")
print("")

-- Core / closures
for _, name in ipairs({
    "checkcaller",
    "clonefunction",
    "getcallingscript",
    "getscriptclosure",
    "hookfunction",
    "iscclosure",
    "islclosure",
    "isexecutorclosure",
    "loadstring",
    "newcclosure",
}) do
    testExists(name)
end

if exists("checkcaller") then
    test("checkcaller", function()
        assert(checkcaller() == true, "executor test scope was not identified as caller")
    end)
end

if exists("clonefunction") then
    test("clonefunction behaviour", function()
        local function original()
            return 42
        end
        local copy = clonefunction(original)
        assert(type(copy) == "function", "clone is not a function")
        assert(copy ~= original, "clone aliases the original closure")
        assert(copy() == original(), "clone returned a different result")
    end)
end

if exists("hookfunction") then
    test("hookfunction behaviour", function()
        local function target()
            return "original"
        end
        local old = hookfunction(target, function()
            return "replacement"
        end)
        assert(target() == "replacement", "hook did not replace the target")
        assert(old() == "original", "hook did not return the original closure")
    end)
end

if exists("newcclosure") and exists("iscclosure") then
    test("newcclosure behaviour", function()
        local function target()
            return true
        end
        local wrapped = newcclosure(target)
        assert(wrapped ~= target, "newcclosure returned the same closure")
        assert(wrapped() == true, "wrapped closure changed the result")
        assert(iscclosure(wrapped) == true, "wrapped closure is not reported as C closure")
    end)
end

if exists("loadstring") then
    test("loadstring behaviour", function()
        local fn, err = loadstring("return ... + 1")
        assert(fn ~= nil, tostring(err))
        assert(fn(41) == 42, "compiled function returned an unexpected value")

        local badFn, badErr = loadstring("this is not valid Luau")
        assert(badFn == nil and type(badErr) == "string", "compiler errors were not reported")
    end)
end

-- Crypt
for _, name in ipairs({
    "crypt.base64encode",
    "crypt.base64decode",
    "crypt.encrypt",
    "crypt.decrypt",
    "crypt.generatebytes",
    "crypt.generatekey",
    "crypt.hash",
}) do
    testExists(name)
end

if exists("crypt.base64encode") and exists("crypt.base64decode") then
    test("crypt.base64 round-trip", function()
        local source = "UNC compatibility test"
        local encoded = crypt.base64encode(source)
        assert(type(encoded) == "string" and #encoded > 0, "encode returned an invalid value")
        assert(crypt.base64decode(encoded) == source, "base64 round-trip failed")
    end)
end

if exists("crypt.generatekey") and exists("crypt.generatebytes") then
    test("crypt key/bytes generation", function()
        local key = crypt.generatekey()
        local bytes = crypt.generatebytes(32)
        assertType(key, "string", "generated key")
        assertType(bytes, "string", "generated bytes")
        assert(#key > 0 and #bytes > 0, "empty cryptographic output")
    end)
end

if exists("crypt.hash") then
    test("crypt.hash", function()
        local hash = crypt.hash("UNC", "sha256")
        assertType(hash, "string", "SHA-256 hash")
        assert(#hash > 0, "hash is empty")
    end)
end

-- Debug
for _, name in ipairs({
    "debug.getconstant",
    "debug.getconstants",
    "debug.getinfo",
    "debug.getproto",
    "debug.getprotos",
    "debug.getstack",
    "debug.getupvalue",
    "debug.getupvalues",
    "debug.setconstant",
    "debug.setstack",
    "debug.setupvalue",
}) do
    testExists(name)
end

if exists("debug.getconstant") then
    test("debug.getconstant", function()
        local function target()
            return "hello"
        end
        local constant = debug.getconstant(target, 1)
        assert(constant == "hello", "unexpected first constant")
    end)
end

if exists("debug.getconstants") then
    test("debug.getconstants", function()
        local function target()
            local value = "UNC"
            return value
        end
        local constants = debug.getconstants(target)
        assert(type(constants) == "table", "constants is not a table")
        assert(#constants > 0, "constants table is empty")
    end)
end

if exists("debug.getinfo") then
    test("debug.getinfo", function()
        local function target(a)
            return a
        end
        local info = debug.getinfo(target)
        assert(type(info) == "table", "debug.getinfo did not return a table")
        assert(type(info.func) == "function", "info.func is not a function")
        assert(type(info.source) == "string", "info.source is not a string")
    end)
end

if exists("debug.getupvalue") then
    test("debug.getupvalue", function()
        local captured = "UNC"
        local function target()
            return captured
        end
        assert(debug.getupvalue(target, 1) == captured, "unexpected upvalue")
    end)
end

if exists("debug.getupvalues") then
    test("debug.getupvalues", function()
        local captured = "UNC"
        local function target()
            return captured
        end
        local values = debug.getupvalues(target)
        assert(type(values) == "table", "upvalues is not a table")
        assert(values[1] == captured, "unexpected first upvalue")
    end)
end

-- Filesystem
for _, name in ipairs({
    "readfile",
    "writefile",
    "appendfile",
    "listfiles",
    "isfile",
    "isfolder",
    "makefolder",
    "delfile",
    "delfolder",
    "loadfile",
    "dofile",
}) do
    testExists(name)
end

if exists("writefile") and exists("readfile") and exists("isfile") then
    test("filesystem read/write", function()
        local path = ".unc_test_io.txt"
        writefile(path, "UNC")
        assert(isfile(path), "test file was not created")
        assert(readfile(path) == "UNC", "readfile returned unexpected contents")
        if exists("delfile") then
            delfile(path)
            assert(not isfile(path), "test file was not deleted")
        end
    end)
end

if exists("makefolder") and exists("isfolder") and exists("delfolder") then
    test("filesystem folder lifecycle", function()
        local path = ".unc_test_folder"
        if isfolder(path) then
            delfolder(path)
        end
        makefolder(path)
        assert(isfolder(path), "folder was not created")
        delfolder(path)
        assert(not isfolder(path), "folder was not deleted")
    end)
end

-- Input
for _, name in ipairs({
    "isrbxactive",
    "mouse1click",
    "mouse1press",
    "mouse1release",
    "mouse2click",
    "mouse2press",
    "mouse2release",
    "mousemoveabs",
    "mousemoverel",
    "mousescroll",
}) do
    testExists(name)
end

if exists("isrbxactive") then
    test("isrbxactive", function()
        assertType(isrbxactive(), "boolean", "isrbxactive result")
    end)
end

-- Instances / reflection
for _, name in ipairs({
    "fireclickdetector",
    "getcallbackvalue",
    "getconnections",
    "getcustomasset",
    "gethiddenproperty",
    "sethiddenproperty",
    "gethui",
    "getinstances",
    "getnilinstances",
    "isscriptable",
    "setscriptable",
    "setrbxclipboard",
}) do
    testExists(name)
end

if exists("getcallbackvalue") then
    test("getcallbackvalue", function()
        local bindable = Instance.new("BindableFunction")
        local callback = function() end
        bindable.OnInvoke = callback
        assert(getcallbackvalue(bindable, "OnInvoke") == callback, "callback value mismatch")
    end)
end

if exists("getconnections") then
    test("getconnections", function()
        local event = Instance.new("BindableEvent")
        local connection = event.Event:Connect(function() end)
        local connections = getconnections(event.Event)
        assert(type(connections) == "table" and #connections > 0, "no connections returned")
        assert(type(connections[1].Disconnect) == "function", "connection lacks Disconnect")
        connection:Disconnect()
    end)
end

if exists("isscriptable") and exists("setscriptable") then
    test("scriptability", function()
        local fire = Instance.new("Fire")
        local before = isscriptable(fire, "Size")
        assert(before == true, "normal Size property was not scriptable")
        local previous = setscriptable(fire, "size_xml", true)
        assert(previous == false, "unexpected previous state for size_xml")
        assert(isscriptable(fire, "size_xml") == true, "setscriptable did not enable the property")
    end)
end

-- Metatables
for _, name in ipairs({
    "getrawmetatable",
    "hookmetamethod",
    "getnamecallmethod",
    "isreadonly",
    "setrawmetatable",
    "setreadonly",
}) do
    testExists(name)
end

if exists("getrawmetatable") then
    test("getrawmetatable", function()
        local mt = { __metatable = "locked" }
        local object = setmetatable({}, mt)
        assert(getrawmetatable(object) == mt, "raw metatable mismatch")
    end)
end

if exists("isreadonly") and exists("setreadonly") then
    test("readonly table", function()
        local object = { value = false }
        table.freeze(object)
        assert(isreadonly(object) == true, "frozen table is not readonly")
        setreadonly(object, false)
        object.value = true
        assert(object.value == true, "readonly state was not changed")
    end)
end

-- Miscellaneous
for _, name in ipairs({
    "identifyexecutor",
    "lz4compress",
    "lz4decompress",
    "messagebox",
    "queue_on_teleport",
    "request",
    "setclipboard",
    "setfpscap",
}) do
    testExists(name)
end

if exists("identifyexecutor") then
    test("identifyexecutor", function()
        local name, version = identifyexecutor()
        assertType(name, "string", "executor name")
        if version ~= nil then
            assertType(version, "string", "executor version")
        end
    end)
end

if exists("lz4compress") and exists("lz4decompress") then
    test("lz4 round-trip", function()
        local source = "UNC compression test"
        local compressed = lz4compress(source)
        assertType(compressed, "string", "compressed data")
        assert(lz4decompress(compressed, #source) == source, "LZ4 round-trip failed")
    end)
end

if exists("request") then
    test("request", function()
        local response = request({
            Url = "https://httpbin.org/status/204",
            Method = "GET",
        })
        assert(type(response) == "table", "request did not return a table")
        assert(type(response.StatusCode) == "number", "StatusCode is not a number")
    end)
end

-- Scripts / environments
for _, name in ipairs({
    "getgc",
    "getgenv",
    "getloadedmodules",
    "getrenv",
    "getrunningscripts",
    "getscriptbytecode",
    "getscripthash",
    "getscripts",
    "getsenv",
    "getthreadidentity",
    "setthreadidentity",
}) do
    testExists(name)
end

if exists("getgenv") then
    test("getgenv", function()
        local key = "__UNC_TEST_GLOBAL"
        getgenv()[key] = true
        assert(getgenv()[key] == true, "executor global could not be written")
        getgenv()[key] = nil
    end)
end

if exists("getgc") then
    test("getgc", function()
        local gc = getgc()
        assert(type(gc) == "table", "getgc did not return a table")
        assert(#gc > 0, "getgc returned an empty table")
    end)
end

if exists("getloadedmodules") then
    test("getloadedmodules", function()
        local modules = getloadedmodules()
        assert(type(modules) == "table", "getloadedmodules did not return a table")
        if #modules > 0 then
            assert(typeof(modules[1]) == "Instance", "first module is not an Instance")
        end
    end)
end

if exists("getrunningscripts") then
    test("getrunningscripts", function()
        local scripts = getrunningscripts()
        assert(type(scripts) == "table", "getrunningscripts did not return a table")
    end)
end

if exists("getthreadidentity") then
    test("getthreadidentity", function()
        assertType(getthreadidentity(), "number", "thread identity")
    end)
end

-- Drawing
for _, name in ipairs({
    "Drawing",
    "Drawing.new",
    "Drawing.Fonts",
    "isrenderobj",
    "getrenderproperty",
    "setrenderproperty",
    "cleardrawcache",
}) do
    testExists(name)
end

if exists("Drawing.new") then
    test("Drawing.new", function()
        local object = Drawing.new("Square")
        object.Visible = false
        assert(type(object) == "userdata" or type(object) == "table", "Drawing.new returned an invalid object")
        if object.Destroy then
            object:Destroy()
        end
    end)
end

if exists("Drawing.Fonts") then
    test("Drawing.Fonts", function()
        assert(type(Drawing.Fonts) == "table", "Drawing.Fonts is not a table")
        assert(Drawing.Fonts.UI ~= nil, "UI font is missing")
        assert(Drawing.Fonts.System ~= nil, "System font is missing")
        assert(Drawing.Fonts.Plex ~= nil, "Plex font is missing")
        assert(Drawing.Fonts.Monospace ~= nil, "Monospace font is missing")
    end)
end

-- WebSocket
for _, name in ipairs({
    "WebSocket",
    "WebSocket.connect",
}) do
    testExists(name)
end

if exists("WebSocket.connect") then
    test("WebSocket.connect", function()
        local ws = WebSocket.connect("ws://echo.websocket.events")
        assert(ws ~= nil, "WebSocket.connect returned nil")
        assert(type(ws.Send) == "function", "WebSocket.Send is missing")
        assert(type(ws.Close) == "function", "WebSocket.Close is missing")
        ws:Close()
    end)
end

print("")
print("UNC Summary")
print("===========")
print(("✅ Passed: %d"):format(passed))
print(("⛔ Failed: %d"):format(failed))
print(("⚠️ Missing: %d"):format(missing))
print(("📊 Behavioural success rate: %d%%"):format(
    (passed + failed) > 0 and math.floor((passed / (passed + failed)) * 100 + 0.5) or 0
))
print("")

return {
    passed = passed,
    failed = failed,
    missing = missing,
    results = results,
}
