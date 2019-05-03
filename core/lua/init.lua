_G.TEST = (os.getenv("GOLUWA_ARG_LINE") or ""):find("RUN_TEST", nil, true)

if TEST then
	jit.off(true, true)
	local call_count = {}
	debug.sethook(function(event, line) 
		if event == "call" then
			local info = debug.getinfo(2, "f")
			call_count[info.func] = (call_count[info.func] or 0) + 1
		end
	end, "c")
	_G.FUNC_CALLS = call_count
end

local start_time = os.clock()

if (os.getenv("GOLUWA_ARG_LINE") or ""):find("--verbose", nil, true) or TEST then
	_G.VERBOSE = true
end

local OS = jit and jit.os:lower() or "unknown"
local ARCH = jit and jit.arch:lower() or "unknown"

if pcall(require, "jit.opt") then
	jit.opt.start(
		"maxtrace=65535", -- 1000 1-65535: maximum number of traces in the cache
		"maxrecord=20000", -- 4000: maximum number of recorded IR instructions
		"maxirconst=500", -- 500: maximum number of IR constants of a trace
		"maxside=100", -- 100: maximum number of side traces of a root trace
		"maxsnap=800", -- 500: maximum number of snapshots for a trace
		"minstitch=0", -- 0: minimum number of IR ins for a stitched trace.
		"hotloop=56", -- 56: number of iterations to detect a hot loop or hot call
		"hotexit=10", -- 10: number of taken exits to start a side trace
		"tryside=4", -- 4: number of attempts to compile a side trace
		"instunroll=500", -- 4: maximum unroll factor for instable loops
		"loopunroll=500", -- 15: maximum unroll factor for loop ops in side traces
		"callunroll=500", -- 3: maximum unroll factor for pseudo-recursive calls
		"recunroll=2", -- 2: minimum unroll factor for true recursion
		"maxmcode=8192", -- 512: maximum total size of all machine code areas in KBytes
		--jit.os == "x64" and "sizemcode=64" or "sizemcode=32", -- Size of each machine code area in KBytes (Windows: 64K)
		"+fold", -- Constant Folding, Simplifications and Reassociation
		"+cse", -- Common-Subexpression Elimination
		"+dce", -- Dead-Code Elimination
		"+narrow", -- Narrowing of numbers to integers
		"+loop", -- Loop Optimizations (code hoisting)
		"+fwd", -- Load Forwarding (L2L) and Store Forwarding (S2L)
		"+dse", -- Dead-Store Elimination
		"+abc", -- Array Bounds Check Elimination
		"+sink", -- Allocation/Store Sinking
		"+fuse" -- Fusion of operands into instructions
	)
	end

--loadfile("core/lua/modules/bytecode_cache.lua")()

local PROFILE_STARTUP = false

if PROFILE_STARTUP then
	local old = io.stdout
	io.stdout = {write = function(_, ...) io.write(...) end}
	require("jit.p").start("rplfvi1")
	io.stdout = old
end

-- put all c functions in a table so we can override them if needed
-- without doing the local oldfunc = print thing over and over again

if not _G._OLD_G then
	local _OLD_G = {}
	if pcall(require, "ffi") then
		_G.ffi = require("ffi")
	end

	for k, v in pairs(_G) do
		if k ~= "_G" then
			local t = type(v)
			if t == "function" then
				_OLD_G[k] = v
			elseif t == "table" then
				_OLD_G[k] = {}
				for k2, v2 in pairs(v) do
					if type(v2) == "function" then
						_OLD_G[k][k2] = v2
					end
				end
			end
		end
	end

	_G.ffi = nil
	_G._OLD_G = _OLD_G
end

do -- constants
	-- enums table
	e = e or {}

	e.USERNAME = _G.USERNAME or tostring(os.getenv("USERNAME") or os.getenv("USER")):gsub(" ", "_"):gsub("%p", "")
	e.INTERNAL_ADDON_NAME = "core"
	e.ROOT_FOLDER = "./"

	if pcall(require, "ffi") then
		local ffi = require("ffi")
		if OS == "windows" then
			ffi.cdef("unsigned long GetCurrentDirectoryA(unsigned long, char *);")
			local buffer = ffi.new("char[260]")
			local length = ffi.C.GetCurrentDirectoryA(260, buffer)
			e.ROOT_FOLDER = ffi.string(buffer, length):gsub("\\", "/") .. "/"
		else
			ffi.cdef("char *realpath(const char *, char *);")
			e.ROOT_FOLDER = ffi.string(ffi.C.realpath(".", nil)) .. "/"
		end
	end

	e.BIN_FOLDER = e.ROOT_FOLDER .. os.getenv("GOLUWA_BINARY_DIR") .. "/"
	e.CORE_FOLDER = e.ROOT_FOLDER .. e.INTERNAL_ADDON_NAME .. "/"

	e.STORAGE_FOLDER = e.ROOT_FOLDER .. "storage/"
	e.USERDATA_FOLDER = e.STORAGE_FOLDER .. "userdata/" .. e.USERNAME:lower() .. "/"
	e.SHARED_FOLDER = e.STORAGE_FOLDER .. "shared/"
	e.CACHE_FOLDER = e.STORAGE_FOLDER .. "cache/"
	e.TEMP_FOLDER = e.STORAGE_FOLDER .. "temp/"
	e.BIN_PATH = "bin/" .. OS .. "_" .. ARCH .. "/"

	-- _G constants. should only contain you need to access a lot like if LINUX then
	_G[e.USERNAME:upper()] = true
	_G[OS:upper()] = true
	_G[ARCH:upper()] = true

	if not _G.PLATFORM then
		if OS == "windows" then
			_G.PLATFORM = "windows"
		elseif OS == "linux" or OS == "osx" or OS == "bsd" then
			_G.PLATFORM = "unix"
			_G.UNIX = true
		else
			_G.PLATFORM = "unknown"
		end
	end
end

_G.runfile = function(path, ...) return assert(loadfile(e.ROOT_FOLDER .. e.INTERNAL_ADDON_NAME .. "/" .. path))(...) end

do
	local fs

	if PLATFORM == "unix" then
		fs = runfile("lua/libraries/platforms/unix/filesystem.lua")
	elseif PLATFORM == "windows" then
		fs = runfile("lua/libraries/platforms/windows/filesystem.lua")
	elseif PLATFORM == "gmod" then
		fs = runfile("lua/libraries/platforms/gmod/filesystem.lua")
	elseif PLATFORM == "unknown" then
		fs = runfile("lua/libraries/platforms/unknown/filesystem.lua")
	end

	package.loaded.fs = fs

	fs.createdir(e.STORAGE_FOLDER)
	fs.createdir(e.STORAGE_FOLDER .. "/userdata/")
	fs.createdir(e.USERDATA_FOLDER)
	fs.createdir(e.CACHE_FOLDER)
	fs.createdir(e.SHARED_FOLDER)
	fs.createdir(e.TEMP_FOLDER)
end

-- standard library extensions
runfile("lua/libraries/extensions/globals.lua")
runfile("lua/libraries/extensions/debug.lua")
runfile("lua/libraries/extensions/string.lua")
runfile("lua/libraries/extensions/table.lua")
runfile("lua/libraries/extensions/os.lua")
runfile("lua/libraries/extensions/ffi.lua")
runfile("lua/libraries/extensions/math.lua")

utility = runfile("lua/libraries/utility.lua")
prototype = runfile("lua/libraries/prototype/prototype.lua")
vfs = runfile("lua/libraries/filesystem/vfs.lua")

vfs.Mount("os:" .. e.STORAGE_FOLDER) -- mount the storage folder to allow requiring files from bin/*
vfs.Mount("os:" .. e.USERDATA_FOLDER, "os:data") -- mount "ROOT/data/users/*username*/" to "/data/"
vfs.Mount("os:" .. e.CACHE_FOLDER, "os:cache")
vfs.Mount("os:" .. e.SHARED_FOLDER, "os:shared")

vfs.MountAddon("os:" .. e.CORE_FOLDER) -- mount "ROOT/"..e.INTERNAL_ADDON_NAME to "/"
vfs.GetAddonInfo(e.INTERNAL_ADDON_NAME).dependencies = {e.INTERNAL_ADDON_NAME} -- prevent init.lua from running later on again
vfs.GetAddonInfo(e.INTERNAL_ADDON_NAME).startup = nil -- prevent init.lua from running later on again

vfs.AddModuleDirectory("lua/modules/")
vfs.AddModuleDirectory("bin/shared/")
vfs.AddModuleDirectory(e.BIN_PATH .. "lua")

if desire("ffi") then
	_G.require("ffi").load = vfs.FFILoadLibrary
end

_G.require = vfs.Require
_G.runfile = vfs.RunFile
_G.R = vfs.GetAbsolutePath -- a nice global for loading resources externally from current dir

package.loaded.bit32 = bit

-- libraries
runfile("lua/libraries/datatypes/buffer.lua")
runfile("lua/libraries/datatypes/tree.lua")
bytepack = runfile("lua/libraries/bytepack.lua") -- string.pack lua implementation
crypto = runfile("lua/libraries/crypto.lua") -- base64 and other hash functions
serializer = runfile("lua/libraries/serializer.lua") -- for serializing lua data in different formats
system = runfile("lua/libraries/system.lua") -- os and luajit related functions like creating windows or changing jit options
event = runfile("lua/libraries/event.lua") -- event handler
utf8 = runfile("lua/libraries/utf8.lua") -- utf8 string library, also extends to string as utf8.len > string.ulen
profiler = runfile("lua/libraries/profiler.lua")
oh = runfile("lua/libraries/oh/oh.lua") -- lua tokenizer, parser and emitter
repl = runfile("lua/libraries/repl.lua")
ffibuild = runfile("lua/libraries/ffibuild.lua") -- used to build binaries
callback = runfile("lua/libraries/callback.lua") -- promise-like library
resource = runfile("lua/libraries/resource.lua") -- used for downloading resources with resource.Download("http://..."):Then(function(path) end)
sockets = runfile("lua/libraries/sockets/sockets.lua")
http = runfile("lua/libraries/http.lua")

if TEST then
	test = runfile("lua/libraries/test.lua")
end

local ok, err = pcall(repl.Start)
if not ok then logn(err) end

-- tries to load all addons
-- some might not load depending on its info.lua file.
-- for instance: "load = CAPSADMIN ~= nil," will make it load
-- only if the CAPSADMIN constant is not nil.
-- this will skip the src folder though

vfs.MountAddons(e.ROOT_FOLDER)

-- this needs to be ran after addons have been mounted as it looks for vmdef.lua and other lua files in binary directories
if jit then
	runfile("lua/libraries/extensions/jit.lua")
end

if VERBOSE then
	logn("[runfile] ", os.clock() - start_time," seconds spent in core/lua/init.lua")
end

e.BOOT_TIME = tonumber(os.getenv("GOLUWA_BOOT_TIME")) or -1
e.INIT_TIME = os.clock() - start_time
e.BOOTIME = os.clock()

if os.getenv("GOLUWA_ARG_LINE") == "build" then
	runfile("lua/ffibuild/libressl.lua")
	runfile("lua/ffibuild/luajit.lua")
	runfile("lua/ffibuild/enet.lua")
	runfile("lua/ffibuild/freeimage.lua")
	runfile("lua/ffibuild/freetype.lua")
	runfile("lua/ffibuild/libarchive.lua")
	runfile("lua/ffibuild/libmp3lame.lua")
	runfile("lua/ffibuild/mpg123.lua")
	runfile("lua/ffibuild/libsndfile.lua")
	runfile("lua/ffibuild/openal.lua")
	runfile("lua/ffibuild/sdl2.lua")

	return
end

-- this can be overriden later, but by default we limit the fps to 30
event.AddListener("FrameEnd", "fps_limit", function()
	system.Sleep(1/30)
end)

event.AddListener("MainLoopStart", function()
	vfs.AutorunAddons()

	-- load everything in goluwa/*/lua/autorun/*USERNAME*/*
	vfs.AutorunAddons(e.USERNAME .. "/")

	system.ExecuteArgs()
end)

vfs.WatchLuaFiles2(true)

-- call goluwa/*/lua/init.lua if it exists
vfs.InitAddons(function()
	event.Call("Initialize")

	if VERBOSE then
		logn("[runfile] total init time took ", os.clock() - start_time, " seconds to execute")
		logn("[runfile] ", vfs.total_loadfile_time, " seconds of that time was overhead spent in loading compiling scripts")
	end

	event.Call("MainLoopStart")
	event.Call("MainLoopStart")
end)

vfs.FetchBniariesForAddon("core")

if TEST then
	debug.sethook()

	local list = {}
	
	for func, count in pairs(FUNC_CALLS) do
		table.insert(list, {func = func, count = count})
	end

	table.sort(list, function(a, b) return a.count > b.count end)

	local max = 30
	logn("========= TOP "..max.." CALLED FUNCTIONS =========")
	for i = 1, max do
		logn(debug.getprettysource(list[i].func, true), " = ", list[i].count)
	end
	logn("===========================================")


	logn("===============RUNNING TESTS===============")
	for _, path in ipairs(vfs.GetFilesRecursive("lua/test/")) do
		test.start(path)
		runfile(path)
		test.stop()
	end
	logn("===========================================")

	if test.fail then
		system.ShutDown(1)
	end

	do
		local lua_time = os.clock() + 0.5
		local system_time = system.GetTime() + 0.25
		local called = false

		event.AddListener("Update", "test", function() 
			called = true

			if system_time < system.GetTime() then
				system.ShutDown(0)
				return e.EVENT_DESTROY
			end

			if lua_time < os.clock() then
				logn("system.GetTime() does not work?: ", system.GetTime())
				system.ShutDown(1)
				return e.EVENT_DESTROY
			end
		end)

		event.Call("Update", system.GetFrameTime())

		if not called then
			logn("Update function could not be called for some reason")
			system.ShutDown(1)
		end
	end
end

local last_time = 0
local i = 0

while system.run == true do
	local time = system.GetTime()

	local dt = time - (last_time or 0)

	system.SetFrameTime(dt)
	system.SetFrameNumber(i)
	system.SetElapsedTime(system.GetElapsedTime() + dt)
	event.Call("Update", dt)
	system.SetInternalFrameTime(system.GetTime() - time)

	i = i + 1
	last_time = time
	event.Call("FrameEnd")
end
repl.Stop()

event.Call("MainLoopStop")
event.Call("MainLoopStop")

event.Call("ShutDown")
collectgarbage()
collectgarbage() -- https://stackoverflow.com/questions/28320213/why-do-we-need-to-call-luas-collectgarbage-twice
os.realexit(os.exitcode)
