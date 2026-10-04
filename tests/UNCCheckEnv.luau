local version1 = "1.0.5"

local passes, fails, skipped, undefined = 0, 0, 0, 0

print("Made by Mari gold!")

wait(3)

local function getGlobal(path)
	local value = getfenv(0)

	while value ~= nil and path ~= "" do
		local name, nextValue = string.match(path, "^([^.]+)%.?(.*)$")
		value = value[name]
		path = nextValue
	end

	return value
end

local function test(name, aliases, callback, status)
	if not getGlobal(name) then
		fails = fails + 1
		warn("⛔ " .. name .. " (missing)")
	elseif status then
		skipped = skipped + 1
		print("⚪ " .. name .. " • " .. status)
	elseif not callback then
		fails = fails + 1
		warn("⛔ " .. name .. " (no behavioural test)")
	else
		local success, message = pcall(callback)
		if success then
			passes = passes + 1
			print("✅ " .. name .. (message and " • " .. message or ""))
		else
			fails = fails + 1
			warn("⛔ " .. name .. " failed: " .. tostring(message))
		end
	end
	local missing={}
	for _,alias in ipairs(aliases) do
		if getGlobal(alias)==nil then table.insert(missing,alias) end
	end
	if #missing>0 then
		undefined = undefined + 1
		warn("⚠️ "..table.concat(missing,", "))
	end
end

print("\n")
print("UNC Environment Check")
print("✅ - Pass, ⛔ - Fail, ⚪ - Skipped/manual, ⚠️ - Missing aliases\n")

-- Cache

test("cache.invalidate", {}, function()
	local container = Instance.new("Folder")
	local part = Instance.new("Part", container)
	cache.invalidate(container:FindFirstChild("Part"))
	assert(part ~= container:FindFirstChild("Part"), "Reference `part` could not be invalidated")
end)

test("cache.iscached", {}, function()
	local part = Instance.new("Part")
	assert(cache.iscached(part), "Part should be cached")
	cache.invalidate(part)
	assert(not cache.iscached(part), "Part should not be cached")
end)

test("cache.replace", {}, function()
	local part=Instance.new("Part"); local fire=Instance.new("Fire")
	cache.replace(part,fire)
	assert(compareinstances(part,fire),"cache.replace did not replace the reference")
end)

test("cloneref", {}, function()
	local part = Instance.new("Part")
	local clone = cloneref(part)
	assert(part ~= clone, "Clone should not be equal to original")
	clone.Name = "Test"
	assert(part.Name == "Test", "Clone should have updated the original")
end)

test("compareinstances", {}, function()
	local part = Instance.new("Part")
	local clone = cloneref(part)
	assert(part ~= clone, "Clone should not be equal to original")
	assert(compareinstances(part, clone), "Clone should be equal to original when using compareinstances()")
end)

-- Closures

local function shallowEqual(t1, t2)
	if t1 == t2 then
		return true
	end

	local UNIQUE_TYPES = {
		["function"] = true,
		["table"] = true,
		["userdata"] = true,
		["thread"] = true,
	}

	for k, v in pairs(t1) do
		if UNIQUE_TYPES[type(v)] then
			if type(t1[k]) ~= type(v) then
				return false
			end
		elseif t2[k] ~= v then
			return false
		end
	end

	for k, v in pairs(t2) do
		if UNIQUE_TYPES[type(v)] then
			if type(t2[k]) ~= type(v) then
				return false
			end
		elseif t1[k] ~= v then
			return false
		end
	end

	return true
end

test("checkcaller", {}, function()
	if type(hookmetamethod) ~= "function" then
		error("hookmetamethod is required for the controlled checkcaller test")
	end

	local observed
	local marker = setmetatable({}, {
		__index = newcclosure(function()
			return false
		end)
	})
	hookmetamethod(marker, "__index", newcclosure(function(self, key)
		observed = checkcaller()
		return observed
	end))

	local ok, err = pcall(function()
		local _ = marker.__UNC_CHECKCALLER
		assert(type(observed) == "boolean", "checkcaller did not return a boolean inside a metamethod hook")
		assert(observed == true, "checkcaller returned false for an executor-originated metamethod call")
	end)

	assert(ok, tostring(err))
end)

test("clonefunction", {}, function()
	local function test()
		return "success"
	end
	local copy = clonefunction(test)
	assert(test() == copy(), "The clone should return the same value as the original")
	assert(test ~= copy, "The clone should not be equal to the original")
end)

test("getcallingscript", {}, function()
	local result = getcallingscript()
	assert(result == nil or typeof(result) == "Instance", "getcallingscript returned an invalid value")
end)

test("getscriptclosure", {"getscriptfunction"}, function()
	local module = game:GetService("ReplicatedStorage").ModuleScript2
	local expected=getrenv().require(module)
	local generated=getscriptclosure(module)()
	assert(type(generated)==type(expected),"Generated closure returned an unexpected value type")
	assert(shallowEqual(expected,generated),"Generated closure did not reproduce the module result")
	module:Destroy()
end)

test("hookfunction", {"replaceclosure"}, function()
	local function test()
		return true
	end
	local ref = hookfunction(test, function()
		return false
	end)
	assert(test() == false, "Function should return false")
	assert(ref() == true, "Original function should return true")
	assert(test ~= ref, "Original function should not be same as the reference")
end)

test("iscclosure", {}, function()
	assert(iscclosure(print) == true, "Function 'print' should be a C closure")
	assert(iscclosure(function() end) == false, "Executor function should not be a C closure")
end)

test("islclosure", {}, function()
	assert(islclosure(print) == false, "Function 'print' should not be a Lua closure")
	assert(islclosure(function() end) == true, "Executor function should be a Lua closure")
end)

test("isexecutorclosure", {"checkclosure", "isourclosure"}, function()
	assert(isexecutorclosure(isexecutorclosure) == true, "Did not return true for an executor global")
	assert(isexecutorclosure(newcclosure(function() end)) == true, "Did not return true for an executor C closure")
	assert(isexecutorclosure(function() end) == true, "Did not return true for an executor Luau closure")
	assert(isexecutorclosure(print) == false, "Did not return false for a Roblox global")
end)

test("loadstring", {}, function()
	local fn,err=loadstring("return ... + 1")
	assert(type(fn)=="function" and err==nil,"Valid source did not compile")
	assert(fn(1)==2,"Compiled function returned an unexpected value")
	local bad,badErr=loadstring("f")
	assert(bad==nil and type(badErr)=="string","Compiler errors must return nil and an error string")
end)

test("newcclosure", {}, function()
	local function test()
		return true
	end
	local testC = newcclosure(test)
	assert(test() == testC(), "New C closure should return the same value as the original")
	assert(test ~= testC, "New C closure should not be same as the original")
	assert(iscclosure(testC), "New C closure should be a C closure")
	local source = debug.info(testC, "s")
	assert(source == "[C]", "debug.info did not identify newcclosure as a C closure (source: " .. tostring(source) .. ")")
end)

-- Crypt

test("crypt.base64encode", {"crypt.base64.encode", "crypt.base64_encode", "base64.encode", "base64_encode"}, function()
	local input = "UNC_BASE64_TEST_\0\255"
	local encoded = crypt.base64encode(input)
	assert(type(encoded) == "string", "Base64 encoding did not return a string")
	assert(encoded ~= input, "Base64 encoding returned the input unchanged")
	assert(encoded == "VU5DX0JBU0U2NF9URVNUXwD/", "Base64 encoding returned an unexpected value")
	assert(crypt.base64decode(encoded) == input, "Base64 encode/decode did not round-trip")
end)

test("crypt.base64decode", {"crypt.base64.decode", "crypt.base64_decode", "base64.decode", "base64_decode"}, function()
	local encoded = "VU5DX0JBU0U2NF9URVNUXwD/"
	local decoded = crypt.base64decode(encoded)
	assert(type(decoded) == "string", "Base64 decoding did not return a string")
	assert(decoded ~= encoded, "Base64 decoding returned the encoded input unchanged")
	assert(decoded == "UNC_BASE64_TEST_\0\255", "Base64 decoding returned an unexpected value")
end)

test("crypt.encrypt", {}, function()
	local key = crypt.generatekey()
	local iv = crypt.generatebytes(16)
	local encrypted, returnedIv = crypt.encrypt("UNC_ENCRYPT_TEST", key, iv, "CBC")
	assert(type(encrypted) == "string", "crypt.encrypt did not return ciphertext")
	assert(encrypted ~= "UNC_ENCRYPT_TEST", "crypt.encrypt returned plaintext unchanged")
	assert(returnedIv == nil or returnedIv == iv, "crypt.encrypt changed the supplied IV unexpectedly")
	assert(crypt.decrypt(encrypted, key, iv, "CBC") == "UNC_ENCRYPT_TEST", "crypt.encrypt/crypt.decrypt did not round-trip")
end)

test("crypt.decrypt", {}, function()
	local key = crypt.generatekey()
	local iv = crypt.generatebytes(16)
	local encrypted = crypt.encrypt("UNC_DECRYPT_TEST", key, iv, "CBC")
	assert(encrypted ~= "UNC_DECRYPT_TEST", "Encryption produced plaintext")
	local decrypted = crypt.decrypt(encrypted, key, iv, "CBC")
	assert(decrypted == "UNC_DECRYPT_TEST", "crypt.decrypt did not recover the original plaintext")
	assert(decrypted ~= encrypted, "crypt.decrypt returned ciphertext unchanged")
end)

test("crypt.generatebytes", {}, function()
	local size = math.random(10, 100)
	local bytes = crypt.generatebytes(size)
	assert(#crypt.base64decode(bytes) == size, "The decoded result should be " .. size .. " bytes long (got " .. #crypt.base64decode(bytes) .. " decoded, " .. #bytes .. " raw)")
end)

test("crypt.generatekey", {}, function()
	local key = crypt.generatekey()
	assert(#crypt.base64decode(key) == 32, "Generated key should be 32 bytes long when decoded")
end)

test("crypt.hash", {}, function()
	local expected = {
		md5 = "098f6bcd4621d373cade4e832627b4f6",
		sha1 = "a94a8fe5ccb19ba61c4c0873d391e987982fbbd3",
		sha384 = "768412320f7b0aa5812fce428dc4706b3cae50e02a64caa16a782249bfe8efc4b7ef1ccb126255d196047dfedf17a0a9",
		sha256 = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
		sha512 = "ee26b0dd4af7e749aa1a8ee3c10ae9923f618980772e473f8819a5d4940e0db27ac185f8a0e1d5f84f88bc887fd67b143732c304cc5fa9ad8e6f57f50028a8ff",
		["sha3-224"] = "3797bf0afbbfca4a7bbba7602a2b552746876517a7f9b7ce2db0ae7b",
		["sha3-256"] = "36f028580bb02cc8272a9a020f4200e346e276ae664e45ee80745574e2f5ab80",
		["sha3-512"] = "9ece086e9bac491fac5c1d1046ca11d737b92a2b2ebd93f005d7b710110c0a678288166e7fbe796883a4f2e9b3ca9f484f521d0ce464345cc1aec96779149c14",
	}
	for algorithm, digest in pairs(expected) do
		local hash = crypt.hash("test", algorithm)
		assert(type(hash) == "string", "crypt.hash did not return a string for " .. algorithm)
		assert(hash == digest, "crypt.hash returned an unexpected digest for " .. algorithm)
		assert(hash ~= "test", "crypt.hash returned the input unchanged for " .. algorithm)
	end
end)

--- Debug

test("debug.getconstant", {}, function()
	local function target() print("UNC_CONSTANT_SENTINEL") end
	local p,s=false,false
	for i=1,64 do local ok,v=pcall(debug.getconstant,target,i); if not ok then break end; if v=="print" then p=true end; if v=="UNC_CONSTANT_SENTINEL" then s=true end end
	assert(p and s,"getconstant did not expose expected constants")
end)

test("debug.getconstants", {}, function()
	local function target() print("UNC_CONSTANT_A","UNC_CONSTANT_B") end
	local values=debug.getconstants(target); assert(type(values)=="table","getconstants must return a table")
	local x,y,p=false,false,false
	for _,v in pairs(values) do if v=="UNC_CONSTANT_A" then x=true elseif v=="UNC_CONSTANT_B" then y=true elseif v=="print" then p=true end end
	assert(x and y and p,"getconstants did not expose expected constants")
end)

test("debug.getinfo", {}, function()
	local types = {
		source = "string",
		short_src = "string",
		func = "function",
		what = "string",
		currentline = "number",
		name = "string",
		nups = "number",
		numparams = "number",
		is_vararg = "number",
	}
	local function test(...)
		print(...)
	end
	local info = debug.getinfo(test)
	for k, v in pairs(types) do
		assert(info[k] ~= nil, "Did not return a table with a '" .. k .. "' field")
		assert(type(info[k]) == v, "Did not return a table with " .. k .. " as a " .. v .. " (got " .. type(info[k]) .. ")")
	end
end)

test("debug.getproto", {}, function()
	local function test()
		local function proto()
			return "UNC_PROTO_1"
		end
	end
	local list = debug.getproto(test, 1, true)
	assert(type(list) == "table" and type(list[1]) == "function", "getproto did not return the inner closure")
	assert(list[1]() == "UNC_PROTO_1", "getproto returned a non-functional closure")
	local raw = debug.getproto(test, 1, false)
	if typeof(raw) == "ProtoProxy" then
		for i, const in ipairs(debug.getconstants(raw)) do
			assert((i == 1 and const == "UNC_PROTO_1"), "ProtoProxy is not a return real values")
		end
		assert(typeof(raw) == "ProtoProxy", "getproto(..., false) did not return a ProtoProxy")
	elseif type(raw) == "function" then
		assert(raw() == "UNC_PROTO_1", "getproto(..., false) did not return a real value")
		assert(type(raw) == "function", "getproto(..., false) did not return a function")
	end
end)

test("debug.getprotos", {}, function()
	local function test()
		local function _1() return "UNC_PROTO_1" end
		local function _2() return "UNC_PROTO_2" end
		local function _3() return "UNC_PROTO_3" end
	end
	local protos = debug.getprotos(test)
	assert(type(protos) == "table" and #protos >= 3, "getprotos did not expose all nested prototypes")
	local seen = {}
	for i = 1, 3 do
		local proto = debug.getproto(test, i, true)[1]
		assert(type(proto) == "function", "getprotos/getproto returned a non-function at index " .. i)
		seen[proto()] = true
	end
	assert(seen.UNC_PROTO_1 and seen.UNC_PROTO_2 and seen.UNC_PROTO_3, "getprotos did not expose the expected distinct prototypes")
end)

test("debug.getstack", {}, function()
	local function target()
		local first = "UNC_STACK_A"
		local second = "UNC_STACK_B"
		local all = debug.getstack(1)
		assert(type(all) == "table", "getstack(level) did not return a table")
		local foundFirst, foundSecond = false, false
		for _, value in pairs(all) do
			if value == first then foundFirst = true end
			if value == second then foundSecond = true end
		end
		assert(foundFirst and foundSecond, "getstack(level) did not expose the active local variables")
	end
	target()
end)

test("debug.getupvalue", {}, function()
	local uv=function() end; local function target() return uv end; local found=false
	for i=1,32 do local ok,v=pcall(debug.getupvalue,target,i); if not ok then break end; if v==uv then found=true break end end
	assert(found,"getupvalue could not locate the captured function")
end)

test("debug.getupvalues", {}, function()
	local uv=function() end; local function target() return uv end; local values=debug.getupvalues(target)
	assert(type(values)=="table","getupvalues must return a table"); local found=false
	for _,v in pairs(values) do if v==uv then found=true break end end
	assert(found,"getupvalues did not contain the captured function")
end)

test("debug.setconstant", {}, function()
	local function target() return "UNC_OLD_CONSTANT" end; local index
	for i=1,64 do local ok,v=pcall(debug.getconstant,target,i); if not ok then break end; if v=="UNC_OLD_CONSTANT" then index=i break end end
	assert(index,"Could not locate target constant"); debug.setconstant(target,index,"UNC_NEW_CONSTANT")
	assert(target()=="UNC_NEW_CONSTANT","debug.setconstant did not change the target constant")
end)

test("debug.setstack", {}, function()
	local hivalue="UNC_OLD_STACK2"; 
	local function target()
		local value="UNC_OLD_STACK"; 
		local index
		for i=1,32 do 
			local ok,v=pcall(debug.getstack,1,i); 
			if not ok then 
				break 
			end; 
			if v==value then 
				index=i 
				break 
			end 
		end
		local index2
		for i=1,32 do 
			local ok,v=pcall(debug.getstack,2,i); 
			if not ok then 
				break 
			end; 
			if v==hivalue then 
				index2=i 
				break 
			end 
		end
		assert(index,"Could not locate target stack slot"); 
		debug.setstack(1,index,"UNC_NEW_STACK");
		debug.setstack(2,index,"UNC_NEW_STACK");
		task.wait()
		assert(debug.getstack(1,index)=="UNC_NEW_STACK","debug.setstack did not change the target stack slot")
	end
	target()
	assert(hivalue =="UNC_NEW_STACK","debug.setstack did not change the target stack slot")
end)

test("debug.setupvalue", {}, function()
	local uv="UNC_OLD_UPVALUE"; 
	local function target() return uv end; 
	local index
	for i=1,32 do local ok,v=pcall(debug.getupvalue,target,i); if not ok then break end; if v==uv then index=i break end end
	assert(index,"Could not locate target upvalue"); 
	debug.setupvalue(target,index,"UNC_NEW_UPVALUE")
	assert(target()=="UNC_NEW_UPVALUE","debug.setupvalue did not change the target upvalue")
end)

test("readfile", {}, function()
	writefile(".tests/readfile.txt", "success")
	assert(readfile(".tests/readfile.txt") == "success", "Did not return the contents of the file")
end)

test("listfiles", {}, function()
	local root=".tests/listfiles"; makefolder(root)
	local a=root.."/test_1.txt"; local b=root.."/test_2.txt"; writefile(a,"A"); writefile(b,"B")
	local files=listfiles(root); local fa,fb=false,false
	for _,path in ipairs(files) do if path==a or string.match(path,"test_1%.txt$") then fa=true end; if path==b or string.match(path,"test_2%.txt$") then fb=true end end
	assert(fa and fb,"listfiles did not return both created files")
end)

test("writefile", {}, function()
	writefile(".tests/writefile.txt", "success")
	assert(readfile(".tests/writefile.txt") == "success", "Did not write the file")
	local requiresFileExt = pcall(function()
		writefile(".tests/writefile", "success")
		assert(isfile(".tests/writefile.txt"))
	end)
	if not requiresFileExt then
		return "This executor requires a file extension in writefile"
	end
end)

test("makefolder", {}, function()
	makefolder(".tests/makefolder")
	assert(isfolder(".tests/makefolder"), "Did not create the folder")
end)

test("appendfile", {}, function()
	writefile(".tests/appendfile.txt", "su")
	appendfile(".tests/appendfile.txt", "cce")
	appendfile(".tests/appendfile.txt", "ss")
	assert(readfile(".tests/appendfile.txt") == "success", "Did not append the file")
end)

test("isfile", {}, function()
	writefile(".tests/isfile.txt", "success")
	assert(isfile(".tests/isfile.txt") == true, "Did not return true for a file")
	assert(isfile(".tests") == false, "Did not return false for a folder")
	assert(isfile(".tests/doesnotexist.exe") == false, "Did not return false for a nonexistent path (got " .. tostring(isfile(".tests/doesnotexist.exe")) .. ")")
end)

test("isfolder", {}, function()
	assert(isfolder(".tests")==true,"Did not identify the test folder")
	local missing=".tests/missing_"..tostring(math.floor(os.clock()*1000000))
	assert(isfolder(missing)==false,"Nonexistent path was reported as a folder")
end)

test("delfolder", {}, function()
	makefolder(".tests/delfolder")
	delfolder(".tests/delfolder")
	assert(isfolder(".tests/delfolder") == false, "Failed to delete folder (isfolder = " .. tostring(isfolder(".tests/delfolder")) .. ")")
end)

test("delfile", {}, function()
	writefile(".tests/delfile.txt", "Hello, world!")
	delfile(".tests/delfile.txt")
	assert(isfile(".tests/delfile.txt") == false, "Failed to delete file (isfile = " .. tostring(isfile(".tests/delfile.txt")) .. ")")
end)

test("loadfile", {}, function()
	local path=".tests/loadfile.txt"; writefile(path,"return ... + 1")
	local fn=assert(loadfile(path)); assert(fn(1)==2,"Failed to load a file with arguments")
	writefile(path,"f"); local bad,err=loadfile(path); assert(bad==nil and type(err)=="string","Compiler error did not return nil plus an error")
end)

test("isrbxactive", {"isgameactive"}, function()
	assert(type(isrbxactive()) == "boolean", "Did not return a boolean value")
end)

if not gethui then
	function gethui() return game:GetService("Players").LocalPlayer.PlayerGui end
end

-- 1. 테스트용 공통 UI 생성 (재활용)
local gui = Instance.new("ScreenGui")
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = gethui()

local button = Instance.new("TextButton")
button.Size = UDim2.fromOffset(200, 200)
button.Position = UDim2.fromOffset(100, 100)
button.Text = "UNC MOUSE TEST"
button.Active = true
button.Selectable = true
button.Parent = gui

task.wait(0.2)

local btnX = button.AbsolutePosition.X + (button.AbsoluteSize.X / 2)
local btnY = button.AbsolutePosition.Y + (button.AbsoluteSize.Y / 2)

if mousemoveabs then
	mousemoveabs(btnX + 1, btnY + 1)
	mousemoveabs(btnX, btnY)
end
task.wait(0.5)

test("mouse1click", {}, function()
	local clicked = false
	local conn = button.MouseButton1Click:Connect(function()
		clicked = true
	end)

	task.wait(0.2)

	mouse1click()
	task.wait(0.2)
	mouse1click()

	task.wait(0.2)

	assert(clicked, "mouse1click did not activate the GUI button at the cursor position")
end)

-- [1] mouse1press (누른 뒤 반드시 mouse1release로 해제)
test("mouse1press", {}, function()
	local pressed = false
	local conn = button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			pressed = true
		end
	end)

	mouse1press()
	task.wait(0.1)

	mouse1release()
	conn:Disconnect()

	assert(pressed, "mouse1press did not activate the GUI button at the cursor position.")
end)


-- [2] mouse1release
test("mouse1release", {}, function()
	local released = false
	local conn = button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			released = true
		end
	end)

	mouse1press()
	task.wait(0.05)
	mouse1release()
	task.wait(0.1)

	conn:Disconnect()

	assert(released, "mouse1release did not release the GUI button at the cursor position.")
end)


-- [4] mouse2press
test("mouse2press", {}, function()
	local pressed = false
	local conn = button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			pressed = true
		end
	end)

	mouse2press()
	task.wait(0.1)

	-- 우클릭 누름 해제
	mouse2release()
	conn:Disconnect()

	assert(pressed, "mouse2press did not activate the GUI button at the cursor position.")
end)


-- [5] mouse2release
test("mouse2release", {}, function()
	local released = false
	local conn = button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			released = true
		end
	end)

	mouse2press()
	task.wait(0.05)
	mouse2release()
	task.wait(0.1)

	conn:Disconnect()

	assert(released, "mouse2release did not release the GUI button at the cursor position.")
end)


-- [6] mouse2click
test("mouse2click", {}, function()
	local clicked = false
	local conn = button.MouseButton2Click:Connect(function()
		clicked = true
	end)

	mouse2click()
	task.wait(0.1)

	conn:Disconnect()

	assert(clicked, "mouse2click did not activate the GUI button at the cursor position.")
end)

button:Destroy()
gui:Destroy()

test("mousescroll", {}, function()
	local gui = Instance.new("ScreenGui")
	gui.IgnoreGuiInset = true
	gui.Parent = gethui()

	local frame = Instance.new("ScrollingFrame")
	frame.Size = UDim2.fromOffset(300, 300)
	frame.Position = UDim2.fromOffset(100, 100)
	frame.CanvasSize = UDim2.fromOffset(300, 2000)
	frame.Active = true
	frame.Selectable = true
	frame.Parent = gui

	task.wait(0.1)

	local targetX = frame.AbsolutePosition.X + (frame.AbsoluteSize.X / 2)
	local targetY = frame.AbsolutePosition.Y + (frame.AbsoluteSize.Y / 2)
	mousemoveabs(targetX, targetY)

	task.wait(0.2)

	frame.CanvasPosition = Vector2.new(0, 500)
	task.wait(0.1)

	local before = frame.CanvasPosition.Y

	mousescroll(-120)
	task.wait(0.1)

	local after = frame.CanvasPosition.Y

	frame:Destroy()
	gui:Destroy()

	assert(after ~= before, string.format("mousescroll did not scroll the GUI at the cursor position. (before: %d, atfer: %d)", before, after))
end)

test("fireclickdetector", {}, function()
	local part=Instance.new("Part",workspace); local detector=Instance.new("ClickDetector",part); local fired=false
	detector.MouseClick:Connect(function() fired=true end); fireclickdetector(detector); task.wait(); part:Destroy()
	assert(fired,"fireclickdetector did not fire MouseClick")
end)

test("getcallbackvalue", {}, function()
	local bindable=Instance.new("BindableFunction")
	local callback=function() return "UNC_CALLBACK" end
	bindable.OnInvoke=callback
	assert(getcallbackvalue(bindable,"OnInvoke")==callback,"Did not return the exact callback")
	assert(bindable:Invoke()=="UNC_CALLBACK","BindableFunction callback is not functional")
end)

test("getconnections", {}, function()
	local bindable=Instance.new("BindableEvent"); 
	local fired=false
	bindable.Event:Connect(function() fired=true end)
	local connections=getconnections(bindable.Event)
	assert(type(connections)=="table" and #connections>0,"getconnections returned no connections")
	local connection=connections[1]
	assert(type(connection.Function)=="function","Connection.Function is missing")
	assert(type(connection.Disconnect)=="function","Connection.Disconnect is missing")
	assert(type(connection.Enabled)=="boolean","Connection.Enabled is missing")
	connection:Fire(); task.wait(); assert(fired,"Connection:Fire() did not invoke the callback")
end)

test("getcustomasset", {}, function()
	writefile(".tests/getcustomasset.txt", "success")
	local contentId = getcustomasset(".tests/getcustomasset.txt")
	assert(type(contentId) == "string", "Did not return a string")
	assert(#contentId > 0, "Returned an empty string")
	assert(string.match(contentId, "rbxasset://") == "rbxasset://", "Did not return an rbxasset url")
end)

test("gethiddenproperty", {}, function()
	local fire = Instance.new("Fire")
	local property, isHidden = gethiddenproperty(fire, "size_xml")
	assert(property == 5, "Did not return the correct value")
	assert(isHidden == true, "Did not return whether the property was hidden")
end)

test("sethiddenproperty", {}, function()
	local fire = Instance.new("Fire")
	local hidden = sethiddenproperty(fire, "size_xml", 10)
	assert(hidden, "Did not return true for the hidden property")
	assert(gethiddenproperty(fire, "size_xml") == 10, "Did not set the hidden property")
end)

test("gethui", {}, function()
	local ui = gethui()
	assert(typeof(ui) == "Instance", "gethui did not return an Instance")
	assert(ui:IsDescendantOf(game.CoreGui) or ui:IsA("CoreGui"), "gethui result is not inside CoreGui")
end)

test("getinstances", {}, function()
	local marker=Instance.new("Folder"); local found=false
	for _,v in ipairs(getinstances()) do if typeof(v)=="Instance" and compareinstances(v,marker) then found=true break end end
	assert(found,"getinstances did not include the created Instance")
end)

test("getnilinstances", {}, function()
	local marker=Instance.new("Folder"); local found=false
	for _,v in ipairs(getnilinstances()) do if typeof(v)=="Instance" and compareinstances(v,marker) and v.Parent==nil then found=true break end end
	assert(found,"getnilinstances did not include the created nil-parented Instance")
end)

test("isscriptable", {}, function()
	local fire = Instance.new("Fire")
	assert(isscriptable(fire, "size_xml") == false, "Did not return false for a non-scriptable property (size_xml)")
	assert(isscriptable(fire, "Size") == true, "Did not return true for a scriptable property (Size)")
end)

test("setscriptable", {}, function()
	local fire = Instance.new("Fire")
	local wasScriptable = setscriptable(fire, "nonefull", true)
	task.wait()
	assert(wasScriptable == false, "Did not return false for a non-scriptable property (size_xml)")
	assert(isscriptable(fire, "nonefull") == true, "Did not set the scriptable property")
	assert((fire["nonefull"] or false), "Did not set the scriptable property")
	setscriptable(fire, "nonefull", false)
	task.wait()
	fire:Destroy()
	fire = Instance.new("Fire")
	task.wait()
	assert(isscriptable(fire, "nonefull") == false, "⚠️⚠️ setscriptable persists between unique instances ⚠️⚠️")
	assert((fire["nonefull"] or true), "Did not set the scriptable property")
	fire:Destroy()
end)

test("setrbxclipboard", {}, nil, "No standard UNC clipboard getter exists for automatic round-trip")

test("getrawmetatable", {}, function()
	local metatable = getrawmetatable(game)
	assert(type(metatable) == "table", "getrawmetatable(game) did not return a table")
	assert(type(metatable.__namecall) == "function", "game raw metatable has no __namecall function")
end)

test("hookmetamethod", {}, function()
	local object = setmetatable({}, { __index = newcclosure(function() return false end), __metatable = "Locked!" })
	local ref = hookmetamethod(object, "__index", function() return true end)
	assert(object.test == true, "Failed to hook a metamethod and change the return value")
	assert(ref() == false, "Did not return the original function")
end)

test("getnamecallmethod", {}, function()
	local method
	local ref
	ref = hookmetamethod(game, "__namecall", function(...)
		if not method then
			method = getnamecallmethod()
		end
		return ref(...)
	end)
	game:GetService("Lighting")
	assert(method == "GetService", "Did not get the correct method (GetService)")
end)

test("isreadonly", {}, function()
	local object = {}
	table.freeze(object)
	assert(isreadonly(object), "Did not return true for a read-only table")
end)

test("setrawmetatable", {}, function()
	local object = setmetatable({}, { __index = function() return false end, __metatable = "Locked!" })
	local objectReturned = setrawmetatable(object, { __index = function() return true end })
	assert(object, "Did not return the original object")
	assert(object.test == true, "Failed to change the metatable")
	if objectReturned then
		return objectReturned == object and "Returned the original object" or "Did not return the original object"
	end
end)

test("setreadonly", {}, function()
	local mt = getrawmetatable(game)
	assert(type(mt) == "table", "Could not obtain game raw metatable")
	local oldReadonly = isreadonly(mt)
	setreadonly(mt, false)
	local oldNamecall = mt.__namecall
	local marker = "__UNC_SETREADONLY_TEST__"
	mt.__namecall = newcclosure(function(...)
		return marker
	end)
	local result = game:GetService("Lighting")
	mt.__namecall = oldNamecall
	setreadonly(mt, oldReadonly)
	assert(result == marker, "setreadonly did not permit changing game.__namecall")
end)

-- Miscellaneous

test("identifyexecutor", {"getexecutorname"}, function()
	local name, version = identifyexecutor()
	assert(type(name) == "string" and #name > 0, "identifyexecutor did not return a non-empty executor name")
	if version ~= nil then assert(type(version) == "string", "identifyexecutor version was not a string") end
	print("identifyexecutor:", name, version or "(no version)")
end)

test("lz4compress", {}, function()
	local raw = "Hello, world!"
	local compressed = lz4compress(raw)
	assert(type(compressed) == "string", "Compression did not return a string")
	assert(lz4decompress(compressed, #raw) == raw, "Decompression did not return the original string")
end)

test("lz4decompress", {}, function()
	local raw = "Hello, world!"
	local compressed = lz4compress(raw)
	assert(type(compressed) == "string", "Compression did not return a string")
	assert(lz4decompress(compressed, #raw) == raw, "Decompression did not return the original string")
end)

test("queue_on_teleport", {"queueonteleport"}, function()
	if (shared["queue_on_teleport_tested"] or false) then
		shared["queue_on_teleport_tested"] = false
		return
	end
	if (shared["a_queue_on_teleport_tested"] or false) then
		assert(false, "queue_on_teleport is not worked!")
	end
	shared["a_queue_on_teleport_tested"] = true
	local TeleportService = game:GetService("TeleportService")
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer
	queue_on_teleport([[
        shared["queue_on_teleport_tested"] = true
        shared["a_queue_on_teleport_tested"] = false
        loadstring(game:HttpGet("https://raw.githubusercontent.com/testaccount11262/docs/refs/heads/feat/unc-compatibility-test/tests/UNCCheckEnv.luau?=" .. os.date(), false))()
    ]])
	task.wait(1)
	if #Players:GetPlayers() <= 1 then
		TeleportService:Teleport(game.PlaceId, LocalPlayer)
	else
		TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
	end
	assert(false, "Queue_on_teleport is testing!")
end)

test("request", {"http.request", "http_request"}, function()
	local response=request({Url="https://httpbin.org/status/204",Method="GET"})
	assert(type(response)=="table","Response must be a table")
	assert(type(response.StatusCode)=="number","StatusCode must be a number")
	assert(response.StatusCode==204,"Did not return the expected HTTP status code")
	assert(type(response.Headers)=="table","Headers must be a table")
	assert(type(response.Body)=="string","Body must be a string")
end)

test("setclipboard", {"toclipboard"}, nil, "No standard UNC clipboard getter exists for automatic round-trip")

test("setfpscap", {}, function()
	local heartbeat = game:GetService("RunService").Heartbeat
	local function measure(seconds)
		local frames, started = 0, os.clock()
		while os.clock() - started < seconds do heartbeat:Wait(); frames = frames + 1 end
		return frames / math.max(os.clock() - started, 0.001)
	end
	local oldCap
	local getFpsCap = getGlobal("getfpscap")
	if type(getFpsCap) == "function" then oldCap = getFpsCap() end
	setfpscap(30)
	local capped = measure(2)
	setfpscap(oldCap or 0)
	local restored = measure(1)
	assert(capped >= 15 and capped <= 45, ("30 FPS cap was not observed; measured %.1f FPS"):format(capped))
	assert(restored > 0, "Heartbeat produced no samples")
	return ("Heartbeat %.1f FPS @ cap 30; %.1f FPS after restore"):format(capped, restored)
end)

-- Scripts

test("getgc", {}, function()
	local marker={}; local fn=function() return marker end; local found=false
	for _,v in pairs(getgc()) do if v==marker or v==fn then found=true break end end
	assert(found,"getgc did not expose an executor-created object")
end)

test("getgenv", {}, function()
	local old = getgenv().__TEST_GLOBAL

	getgenv().__TEST_GLOBAL = true
	task.wait()
	assert(__TEST_GLOBAL == true, "getgenv() write did not propagate to the current global environment")

	getgenv().__TEST_GLOBAL = old
	assert(getgenv().__TEST_GLOBAL == old, "Failed to restore the getgenv() value")
end)

test("getloadedmodules", {}, function()
	local module = game:GetService("ReplicatedStorage").ModuleScript
	task.wait()
	getrenv().require(module); 
	local found=false
	task.wait()
	for _,v in ipairs(getloadedmodules()) do 
		if typeof(v)=="Instance" and compareinstances(v,module) then 
			found=true 
			break 
		end 
	end
	assert(found,"getloadedmodules did not include a required ModuleScript")
	module:Destroy()
end)

test("getrenv", {}, function()
	local env = getrenv()
	local tested = game:GetService("Players").LocalPlayer.PlayerScripts.UNC_TEST_BYTECODE_CHECKED
	assert(type(env) == "table", "getrenv() did not return an environment table")
	assert(env._G ~= _G, "The game _G is identical to the executor _G")

	local old = env.__UNC_TEST_RENV
	local marker = {}
	env.__UNC_TEST_RENV = marker
	assert(env.__UNC_TEST_RENV == marker, "getrenv() environment is not writable")
	assert(hookfunction, "Hookfunction is not Exis")
	assert(getsenv, "getsenv is not Exis")
	getrenv().__UNC_TEST_RENV_FUNCTION = function() return "fucked" end
	hookfunction(getrenv().__UNC_TEST_RENV_FUNCTION, function()
		return "PASSED!"
	end)

	tested.Disabled = false

	for _, scr in pairs(getrunningscripts()) do
		if scr.Name == "UNC_TEST_BYTECODE_CHECKED" then
			local env1 = getsenv(scr)
			if env1 then
				assert(env.shared["res"], "Failed getrenv to hook Roblox environment")
			end
		end
	end
	tested.Disabled = true
	env.__UNC_TEST_RENV = old
	assert(env.__UNC_TEST_RENV == old, "Failed to restore getrenv() environment")
end)

test("getrunningscripts", {}, function()
	local target=game:GetService("Players").LocalPlayer.Character.Animate; local found=false
	for _,v in ipairs(getrunningscripts()) do if typeof(v)=="Instance" and compareinstances(v,target) then found=true break end end
	assert(found,"getrunningscripts did not include the running Animate script")
end)

test("getscriptbytecode", {"dumpstring"}, function()
	local animate = game:GetService("Players").LocalPlayer.Character.Animate
	local bytecode = getscriptbytecode(animate)
	assert(type(bytecode) == "string", "Did not return a string for Character.Animate (a " .. animate.ClassName .. ")")
	assert(bytecode == base64decode(game:HttpGet("https://raw.githubusercontent.com/testaccount11262/docs/refs/heads/feat/unc-compatibility-test/tests/Animate.luac", false)), "Did not return a real bytecode for Character.Animate (a " .. animate.ClassName .. ")")
end)

local function checkScriptPattern(sourceCode)
	local code = sourceCode:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")

	local scriptVars = { ["script"] = true }

	local foundNewVar = true
	while foundNewVar do
		foundNewVar = false
		for varName, refName in code:gmatch("local%s+([%w_]+)%s*:%s*[%w_<>%[%]]+%s*=%s*([%w_]+)") do
			if scriptVars[refName] and not scriptVars[varName] then
				scriptVars[varName] = true
				foundNewVar = true
			end
		end
		for varName, refName in code:gmatch("local%s+([%w_]+)%s*=%s*([%w_]+)") do
			if scriptVars[refName] and not scriptVars[varName] then
				scriptVars[varName] = true
				foundNewVar = true
			end
		end
	end

	local isNameSet = false
	for varName in pairs(scriptVars) do
		local pattern = varName .. '%s*%.%s*Name%s*=%s*["\']hi["\']'
		if code:find(pattern) then
			isNameSet = true
			break
		end
	end

	local hasWaitLoop = code:match("while%s+true%s+do.-task%.wait%(%)(.-)end") ~= nil

	return isNameSet and hasWaitLoop
end

test("decompile", {}, function()
	local animate = game:GetService("Players").LocalPlayer.PlayerScripts.UNC_TEST_BYTECODE
	local source = decompile(animate)
	assert(type(source) == "string", "Did not return a string for Character.Animate (a " .. animate.ClassName .. ")")
	assert(checkScriptPattern(source), "Did not return a real source 💀")
end)

test("getscripthash", {}, function()
	local animate = game:GetService("Players").LocalPlayer.Character.Animate:Clone()
	local hash = getscripthash(animate)
	local source = animate.Source
	task.wait()
	animate.Source = "print('Hello, world!')"
	local newHash = getscripthash(animate)
	assert(hash ~= newHash, "Did not return a different hash for a modified script")
	assert(hash == base64decode(game:HttpGet("https://raw.githubusercontent.com/testaccount11262/docs/refs/heads/feat/unc-compatibility-test/tests/animate.hash",false)), "Did not return a real hash for a Animate script")
	assert(newHash == nil, "Did return a nil")
	assert(newHash == getscripthash(animate), "Did not return the same hash for a script with the same source")
	task.wait()
	animate.Source = source
end)

test("getscripts", {}, function()
	local target=game:GetService("Players").LocalPlayer.Character.Animate; local found=false
	for _,v in ipairs(getscripts()) do if typeof(v)=="Instance" and compareinstances(v,target) then found=true break end end
	assert(found,"getscripts did not include the known script")
end)

test("getsenv", {}, function()
	local localScript = game:GetService("Players").LocalPlayer.PlayerScripts.UNC_GETSENV_TEST
	tested.Disabled = false
	task.wait(0.5)

	for _, scr in pairs(getrunningscripts()) do
		if scr.Name == "UNC_GETSENV_TEST" then
			local env = getsenv(scr) 
			if env then 
				forcedEnv = getrenv().shared["__TEST_ENV"] or env.shared["__TEST_ENV"] or {}
				assert(type(env) == "table", "getsenv did not return an environment table")
				assert(env.script == localScript, "getsenv().script is not the target LocalScript")
				assert(env.__UNC_GETSENV_VALUE == "__UNC_GETSENV_VALUE__", "getsenv did not expose the LocalScript environment value")
				assert(type(env.__UNC_GETSENV_FUNCTION_REF) == "function", "getsenv did not expose the LocalScript function")
				assert(env.__UNC_GETSENV_FUNCTION_REF() == "__UNC_GETSENV_OK__", "getsenv returned a non-functional LocalScript closure")
				assert(env.__UNC_GETSENV_FUNCTION_REF == forcedEnv.__UNC_GETSENV_FUNCTION_REF, "getsenv did not return the expected LocalScript closure reference")
			end
		end
	end
	tested.Disabled = true
end)

test("getthreadidentity", {"getidentity", "getthreadcontext", "setthreadidentity", "setidentity", "setthreadcontext"}, function()
	local original = getthreadidentity()
	local target = original == 2 and 8 or 2

	local ok, err = pcall(function()
		setthreadidentity(target)
		assert(getthreadidentity() == target, "setthreadidentity did not change the identity reported by getthreadidentity")
	end)

	local restored, restoreErr = pcall(function()
		setthreadidentity(original)
	end)

	assert(restored, "Failed to restore original thread identity: " .. tostring(restoreErr))
	assert(ok, tostring(err))
end)

-- Drawing

test("Drawing", {}, function() assert(type(Drawing) == "table" or type(Drawing) == "userdata", "Drawing must be an object"); assert(type(Drawing.new) == "function", "Drawing.new must be callable") end)

test("Drawing.new", {}, function()
	local drawing = Drawing.new("Square")
	drawing.Visible = false
	drawing.Size = Vector2.new(32, 32)
	drawing.Position = Vector2.new(100, 100)
	assert(drawing.Visible == false, "Visible did not retain its value")
	assert(drawing.Size.X == 32 and drawing.Size.Y == 32, "Size did not retain its value")
	assert(drawing.Position.X == 100 and drawing.Position.Y == 100, "Position did not retain its value")
	drawing.Visible = true
	assert(drawing.Visible == true, "Visible could not be enabled")
	assert(type(drawing.Destroy) == "function", "Destroy is not callable")
	assert(pcall(function() drawing:Destroy() end), "Drawing:Destroy() should not throw an error")
end)

test("isrenderobj", {}, function()
	local drawing = Drawing.new("Image")
	drawing.Visible = true
	assert(isrenderobj(drawing) == true, "Did not return true for an Image")
	assert(isrenderobj(newproxy()) == false, "Did not return false for a blank table")
end)

test("getrenderproperty", {}, function()
	local drawing = Drawing.new("Image")
	drawing.Visible = true
	assert(type(getrenderproperty(drawing, "Visible")) == "boolean", "Did not return a boolean value for Image.Visible")
	local success, result = pcall(function()
		return getrenderproperty(drawing, "Color")
	end)
	if not success or not result then
		return "Image.Color is not supported"
	end
end)

test("setrenderproperty", {}, function()
	local drawing = Drawing.new("Square")
	drawing.Visible = true
	setrenderproperty(drawing, "Visible", false)
	assert(drawing.Visible == false, "Did not set the value for Square.Visible")
end)

test("cleardrawcache", {}, nil, "No portable oracle for cache contents")

-- WebSocket

test("WebSocket", {}, nil, "WebSocket.connect below is the behavioral test")

test("WebSocket.connect", {}, function()
	local ws = WebSocket.connect("wss://javascript.info/article/websocket/demo/hello")
	assert(type(ws) == "table" or type(ws) == "userdata", "Did not return a table or userdata")
	assert(type(ws.Send) == "function", "Send is missing")
	assert(type(ws.Close) == "function", "Close is missing")
	assert(ws.OnMessage ~= nil, "OnMessage is missing")
	assert(ws.OnClose ~= nil, "OnClose is missing")
	local received, connection
	if type(ws.OnMessage.Connect) == "function" then
		connection = ws.OnMessage:Connect(function(message) received = message end)
	end
	local token = "UNC_WS_" .. tostring(math.floor(os.clock() * 1000000))
	ws:Send(token)
	local deadline = os.clock() + 5
	while received == nil and os.clock() < deadline do task.wait() end
	if connection then connection:Disconnect() end
	ws:Close()
	assert(received == token, "WebSocket echo did not return the sent payload")
end)


print("\n")
print("UNC Summary")
local rate = (passes + fails) > 0 and math.round(passes / (passes + fails) * 100) or 0
print("✅ Tested with a " .. rate .. "% success rate (" .. passes .. " out of " .. (passes + fails) .. ")")
print("⛔ " .. fails .. " tests failed")
print("⚪ " .. skipped .. " tests skipped/manual")
print("⚠️ " .. (undefined or "0") .. " tests have missing aliases")

local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64encode(data: string): string
	local result = {}
	local len = #data
	local i = 1

	while i <= len do
		local b1 = string.byte(data, i) or 0
		local b2 = string.byte(data, i + 1) or 0
		local b3 = string.byte(data, i + 2) or 0

		local n = bit32.lshift(b1, 16) + bit32.lshift(b2, 8) + b3

		local c1 = bit32.extract(n, 18, 6) + 1
		local c2 = bit32.extract(n, 12, 6) + 1
		local c3 = bit32.extract(n, 6, 6) + 1
		local c4 = bit32.extract(n, 0, 6) + 1

		table.insert(result, string.sub(chars, c1, c1))
		table.insert(result, string.sub(chars, c2, c2))

		if i + 1 <= len then
			table.insert(result, string.sub(chars, c3, c3))
		else
			table.insert(result, "=")
		end

		if i + 2 <= len then
			table.insert(result, string.sub(chars, c4, c4))
		else
			table.insert(result, "=")
		end

		i = i + 3
	end

	return table.concat(result)
end

local charset = "1234567890"

function random(length)
	math.randomseed(os.time())
	if length > 0 then
		return random(length - 1) .. charset:sub(math.random(1, #charset), 1)
	else
		return ""
	end
end

local band = bit32.band
local bnot = bit32.bnot
local bor  = bit32.bor
local bxor = bit32.bxor
local lshift = bit32.lshift
local rshift = bit32.rshift
local lrotate = bit32.lrotate

local function add32(...)
	local r = 0
	for i = 1, select("#", ...) do
		r = r + select(i, ...)
	end
	return r % 4294967296
end

local function bytes_to_w(str, idx)
	return bor(
		string.byte(str, idx) or 0,
		lshift(string.byte(str, idx + 1) or 0, 8),
		lshift(string.byte(str, idx + 2) or 0, 16),
		lshift(string.byte(str, idx + 3) or 0, 24)
	)
end

local function w_to_hex(w)
	local s = ""
	for i = 1, 4 do
		s = s .. string.format("%02x", band(w, 0xff))
		w = rshift(w, 8)
	end
	return s
end

local T = {}
for i = 1, 64 do 
	T[i] = math.floor(4294967296 * math.abs(math.sin(i))) 
end

local S = {
	7,12,17,22, 7,12,17,22, 7,12,17,22, 7,12,17,22,
	5, 9,14,20, 5, 9,14,20, 5, 9,14,20, 5, 9,14,20,
	4,11,16,23, 4,11,16,23, 4,11,16,23, 4,11,16,23,
	6,10,15,21, 6,10,15,21, 6,10,15,21, 6,10,15,21
}

local function custom_md5(msg)
	local len = #msg
	local bit_len = len * 8
	msg = msg .. string.char(128)

	while (#msg + 8) % 64 ~= 0 do 
		msg = msg .. string.char(0) 
	end

	for i = 1, 4 do 
		msg = msg .. string.char(band(bit_len, 256 - 1))
		bit_len = rshift(bit_len, 8) 
	end
	for i = 1, 4 do msg = msg .. string.char(0) end

	local h0, h1, h2, h3 = 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476

	for chunk_offset = 1, #msg, 64 do
		local W = {}
		for i = 0, 15 do 
			W[i] = bytes_to_w(msg, chunk_offset + i * 4) 
		end

		local a, b, c, d = h0, h1, h2, h3
		local f, g

		for i = 0, 63 do
			if i <= 15 then
				f = bor(band(b, c), band(bnot(b), d))
				g = i
			elseif i <= 31 then
				f = bor(band(d, b), band(bnot(d), c))
				g = (5 * i + 1) % 16
			elseif i <= 47 then
				f = bxor(bxor(b, c), d)
				g = (3 * i + 5) % 16
			else
				f = bxor(c, bor(b, bnot(d)))
				g = (7 * i) % 16
			end

			local temp = d
			d = c
			c = b
			b = add32(b, lrotate(add32(a, f, T[i + 1], W[g]), S[i + 1]))
			a = temp
		end

		h0 = add32(h0, a)
		h1 = add32(h1, b)
		h2 = add32(h2, c)
		h3 = add32(h3, d)
	end

	return w_to_hex(h0) .. w_to_hex(h1) .. w_to_hex(h2) .. w_to_hex(h3)
end

if not identifyexecutor then
	identifyexecutor = function() return "not 00" end
end
print("Made By Mari Gold!")
print(base64encode(string.sub(identifyexecutor(), 1, 3) .. version1 .. custom_md5(game:HttpGet("https://raw.githubusercontent.com/testaccount11262/docs/refs/heads/feat/unc-compatibility-test/tests/UNCCheckEnv.luau?t=" .. os.date(), false) .. " " .. random(1))))

shared["queue_on_teleport_tested"] = false
shared["a_queue_on_teleport_tested"] = nil
