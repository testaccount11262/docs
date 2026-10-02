local passes, fails, skipped, undefined = 0, 0, 0

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
		fails += 1
		warn("⛔ " .. name .. " (missing)")
	elseif status then
		skipped += 1
		print("⚪ " .. name .. " • " .. status)
	elseif not callback then
		fails += 1
		warn("⛔ " .. name .. " (no behavioural test)")
	else
		local success, message = pcall(callback)
		if success then
			passes += 1
			print("✅ " .. name .. (message and " • " .. message or ""))
		else
			fails += 1
			warn("⛔ " .. name .. " failed: " .. tostring(message))
		end
	end
	local missing={}
	for _,alias in ipairs(aliases) do
		if getGlobal(alias)==nil then table.insert(missing,alias) end
	end
	if #missing>0 then
		undefined+=1
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
		return false
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
	local module=game:GetService("CoreGui").RobloxGui.Modules.Common.Constants
	local expected=getrenv().require(module)
	local generated=getscriptclosure(module)()
	assert(type(generated)==type(expected),"Generated closure returned an unexpected value type")
	assert(shallowEqual(expected,generated),"Generated closure did not reproduce the module result")
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
end)

-- Console

test("rconsoleclear", {"consoleclear"}, nil, "No portable console-state oracle")

test("rconsolecreate", {"consolecreate"}, nil, "No portable console-state oracle")

test("rconsoledestroy", {"consoledestroy"}, nil, "No portable console-state oracle")

test("rconsoleinput", {"consoleinput"}, nil, "Requires interactive console input")

test("rconsoleprint", {"consoleprint"}, nil, "No portable console-output oracle")

test("rconsolesettitle", {"rconsolename", "consolesettitle"}, nil, "No portable console-title oracle")

-- Crypt

test("crypt.base64encode", {"crypt.base64.encode", "crypt.base64_encode", "base64.encode", "base64_encode"}, function()
	assert(crypt.base64encode("test") == "dGVzdA==", "Base64 encoding failed")
end)

test("crypt.base64decode", {"crypt.base64.decode", "crypt.base64_decode", "base64.decode", "base64_decode"}, function()
	assert(crypt.base64decode("dGVzdA==") == "test", "Base64 decoding failed")
end)

test("crypt.encrypt", {}, function()
	local key = crypt.generatekey()
	local encrypted, iv = crypt.encrypt("test", key, nil, "CBC")
	assert(iv, "crypt.encrypt should return an IV")
	local decrypted = crypt.decrypt(encrypted, key, iv, "CBC")
	assert(decrypted == "test", "Failed to decrypt raw string from encrypted data")
end)

test("crypt.decrypt", {}, function()
	local key, iv = crypt.generatekey(), crypt.generatekey()
	local encrypted = crypt.encrypt("test", key, iv, "CBC")
	local decrypted = crypt.decrypt(encrypted, key, iv, "CBC")
	assert(decrypted == "test", "Failed to decrypt raw string from encrypted data")
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
	local algorithms = {'sha1', 'sha384', 'sha512', 'md5', 'sha256', 'sha3-224', 'sha3-256', 'sha3-512'}
	for _, algorithm in ipairs(algorithms) do
		local hash = crypt.hash("test", algorithm)
		assert(hash, "crypt.hash on algorithm '" .. algorithm .. "' should return a hash")
	end
end)

--- Debug

test("debug.getconstant", {}, function()
	local function target() print("UNC_CONSTANT_SENTINEL") end
	local p,s=false,false
	for i=1,64 do local ok,v=pcall(debug.getconstant,target,i); if not ok then break end; if v==print then p=true end; if v=="UNC_CONSTANT_SENTINEL" then s=true end end
	assert(p and s,"getconstant did not expose expected constants")
end)

test("debug.getconstants", {}, function()
	local function target() print("UNC_CONSTANT_A","UNC_CONSTANT_B") end
	local values=debug.getconstants(target); assert(type(values)=="table","getconstants must return a table")
	local x,y,p=false,false,false
	for _,v in pairs(values) do if v=="UNC_CONSTANT_A" then x=true elseif v=="UNC_CONSTANT_B" then y=true elseif v==print then p=true end end
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
			return true
		end
	end
	local proto = debug.getproto(test, 1, true)[1]
	local realproto = debug.getproto(test, 1)
	assert(proto, "Failed to get the inner function")
	assert(proto() == true, "The inner function did not return anything")
	if not realproto() then
		return "Proto return values are disabled on this executor"
	end
end)

test("debug.getprotos", {}, function()
	local function test()
		local function _1()
			return true
		end
		local function _2()
			return true
		end
		local function _3()
			return true
		end
	end
	for i in ipairs(debug.getprotos(test)) do
		local proto = debug.getproto(test, i, true)[1]
		local realproto = debug.getproto(test, i)
		assert(proto(), "Failed to get inner function " .. i)
		if not realproto() then
			return "Proto return values are disabled on this executor"
		end
	end
end)

test("debug.getstack", {}, function()
	local _ = "a" .. "b"
	assert(debug.getstack(1, 1) == "ab", "The first item in the stack should be 'ab'")
	assert(debug.getstack(1)[1] == "ab", "The first item in the stack table should be 'ab'")
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
	local function target()
		local value="UNC_OLD_STACK"; local index
		for i=1,32 do local ok,v=pcall(debug.getstack,1,i); if not ok then break end; if v==value then index=i break end end
		assert(index,"Could not locate target stack slot"); debug.setstack(1,index,"UNC_NEW_STACK")
		assert(debug.getstack(1,index)=="UNC_NEW_STACK","debug.setstack did not change the target stack slot")
	end
	target()
end)

test("debug.setupvalue", {}, function()
	local uv="UNC_OLD_UPVALUE"; local function target() return uv end; local index
	for i=1,32 do local ok,v=pcall(debug.getupvalue,target,i); if not ok then break end; if v==uv then index=i break end end
	assert(index,"Could not locate target upvalue"); debug.setupvalue(target,index,"UNC_NEW_UPVALUE")
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

test("dofile", {}, function()
	local path=".tests/dofile.txt"; writefile(path,"return ... + 1")
	assert(dofile(path,41)==42,"dofile returned an unexpected value"); delfile(path)
end)

test("isrbxactive", {"isgameactive"}, function()
	assert(type(isrbxactive()) == "boolean", "Did not return a boolean value")
end)

test("mouse1click", {}, nil, "No standard UNC state getter exists for automatic verification")

test("mouse1press", {}, nil, "No standard UNC state getter exists for automatic verification")

test("mouse1release", {}, nil, "No standard UNC state getter exists for automatic verification")

test("mouse2click", {}, nil, "No standard UNC state getter exists for automatic verification")

test("mouse2press", {}, nil, "No standard UNC state getter exists for automatic verification")

test("mouse2release", {}, nil, "No standard UNC state getter exists for automatic verification")

test("mousemoveabs", {}, nil, "No standard UNC state getter exists for automatic verification")

test("mousemoverel", {}, nil, "No standard UNC state getter exists for automatic verification")

test("mousescroll", {}, nil, "No standard UNC state getter exists for automatic verification")

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
	local bindable=Instance.new("BindableEvent"); local fired=false
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

test("gethui", {}, nil, "No portable oracle for hidden UI container identity")

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
	local wasScriptable = setscriptable(fire, "size_xml", true)
	assert(wasScriptable == false, "Did not return false for a non-scriptable property (size_xml)")
	assert(isscriptable(fire, "size_xml") == true, "Did not set the scriptable property")
	fire = Instance.new("Fire")
	assert(isscriptable(fire, "size_xml") == false, "⚠️⚠️ setscriptable persists between unique instances ⚠️⚠️")
end)

test("setrbxclipboard", {}, nil, "No standard UNC clipboard getter exists for automatic round-trip")

test("getrawmetatable", {}, function()
	local metatable = { __metatable = "Locked!" }
	local object = setmetatable({}, metatable)
	assert(getrawmetatable(object) == metatable, "Did not return the metatable")
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
	local object = { success = false }
	table.freeze(object)
	setreadonly(object, false)
	object.success = true
	assert(object.success, "Did not allow the table to be modified")
end)

-- Miscellaneous

test("identifyexecutor", {"getexecutorname"}, nil, "Executor identity has no independent portable oracle")

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

test("messagebox", {}, nil, "Requires human confirmation of the native dialog")

test("queue_on_teleport", {"queueonteleport"}, nil, "Requires an actual teleport to verify execution")

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
		while os.clock() - started < seconds do heartbeat:Wait(); frames += 1 end
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
	local env = getgenv()
	local old = env.__TEST_GLOBAL

	env.__TEST_GLOBAL = true
	assert(__TEST_GLOBAL == true, "getgenv() write did not propagate to the current global environment")

	__TEST_GLOBAL = false
	assert(env.__TEST_GLOBAL == false, "Current global write did not propagate back to getgenv()")

	env.__TEST_GLOBAL = old
	assert(env.__TEST_GLOBAL == old, "Failed to restore the getgenv() value")
end)

test("getloadedmodules", {}, function()
	local module=game:GetService("CoreGui").RobloxGui.Modules.Common.Constants; getrenv().require(module); local found=false
	for _,v in ipairs(getloadedmodules()) do if typeof(v)=="Instance" and compareinstances(v,module) then found=true break end end
	assert(found,"getloadedmodules did not include a required ModuleScript")
end)

test("getrenv", {}, function()
	local env = getrenv()
	assert(type(env) == "table", "getrenv() did not return an environment table")
	assert(env._G ~= _G, "The game _G is identical to the executor _G")

	local old = env.__UNC_TEST_RENV
	local marker = {}
	env.__UNC_TEST_RENV = marker
	assert(env.__UNC_TEST_RENV == marker, "getrenv() environment is not writable")
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
end)

test("getscripthash", {}, function()
	local animate = game:GetService("Players").LocalPlayer.Character.Animate:Clone()
	local hash = getscripthash(animate)
	local source = animate.Source
	animate.Source = "print('Hello, world!')"
	task.defer(function()
		animate.Source = source
	end)
	local newHash = getscripthash(animate)
	assert(hash ~= newHash, "Did not return a different hash for a modified script")
	assert(newHash == getscripthash(animate), "Did not return the same hash for a script with the same source")
end)

test("getscripts", {}, function()
	local target=game:GetService("Players").LocalPlayer.Character.Animate; local found=false
	for _,v in ipairs(getscripts()) do if typeof(v)=="Instance" and compareinstances(v,target) then found=true break end end
	assert(found,"getscripts did not include the known script")
end)

test("getsenv", {}, function()
	local animate = game:GetService("Players").LocalPlayer.Character.Animate
	local env = getsenv(animate)
	assert(type(env) == "table", "Did not return a table for Character.Animate (a " .. animate.ClassName .. ")")
	assert(env.script == animate, "The script global is not identical to Character.Animate")
end)

test("thread identity", {"getthreadidentity", "getidentity", "getthreadcontext", "setthreadidentity", "setidentity", "setthreadcontext"}, function()
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
	local ws = WebSocket.connect("wss://echo.websocket.events")
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
print("⚠️ " .. undefined .. " tests have missing aliases")
