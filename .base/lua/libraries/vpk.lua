local vpk = _G.vpk or {}

event.AddListener("VFSMountFile", "vpk_mount", function(path, mount, ext)
	
	if ext == "vpk" then
		
		if mount then
			local pack = vpk.Open(path)
			  
			vfs.Mount({
				id = path, 
				root = "",
				callback = function(type, a, b, c, d, ...)  		
					if type == "attributes" then
						local path = a
						path = path:sub(2) 

						return pack:GetAttributes(path)
					elseif type == "find" then
						local path = a
						
						path = path:sub(2) 
						path = path .. "/"

						return pack:Find(path)
					elseif type == "file" then
						local type = a
						
						if type == "open" then
							local path = b
							path = path:sub(2) 
							
							if not pack:Exists(path) then
								return false, "File does not exist"
							end
							 
							local mode = e.HL_MODE_INVALID
								
							do -- modes
								local str = c
								str = str:lower()
								
								if str:find("w") then
									mode = bit.bor(mode, e.HL_MODE_WRITE)
								end
								
								if str:find("r") then
									mode = bit.bor(mode, e.HL_MODE_READ)
								end
							end
											
							return pack:Open(path, mode)
						elseif type == "read" then
							local handle = b
							local type = c
							local bytes = d

							if type == "bytes" then 
								local buffer, length = pack:Read(handle, bytes)
								
								if length == 0 then return end
								
								return ffi.string(buffer, length)
							end
							
							-- WIP
							-- otherwise just read everything.. 
							return ffi.string(pack:Read(handle))
						elseif type == "close" then
							local handle = b
							
							pack:Close(handle)
						end
					end
				end 
			})
		else
			vfs.Unmount({id = path})
		end
		return true
	end
end)

vpk.opened = vpk.opened or {}

local META = utilities.CreateBaseMeta("vpk")
META.__index = META

function META:__tostring()
	return ("vpk[%i]"):format(self.id)
end
 
function vpk.Open(path, mode)
	path = path:lower()

	if vpk.opened[path] and vpk.opened[path]:IsValid() then 
		vpk.opened[path]:Remove()
	end
	
	local self = utilities.CreateBaseObject("vpk")
	
	setmetatable(self, META)
		
	local type = hl.GetPackageTypeFromName(path)

	local id = ffi.new("unsigned int[1]", 0)
	hl.CreatePackage(type, id)
	self.id = id[0]
	
	hl.BindPackage(self.id)
		hl.PackageOpenFile(path, bit.bor(e.HL_MODE_READ, e.HL_MODE_VOLATILE))
	
		do -- cache all paths (this is fast anyway)
			local paths = {}
			local temp = ffi.new("char[512]")
			
			local item = hl.FolderFindFirst(hl.PackageGetRoot(), "*", e.HL_FIND_ALL)

			while item ~= nil do
				local type = hl.ItemGetType(item)
				
				if type == e.HL_ITEM_FILE then 
					type = "file"
				elseif type == e.HL_ITEM_FOLDER then
					type = "directory"
				else
					type = "other"
				end
				
				hl.ItemGetPath(item, temp, 256)
				
				local str = ffi.string(temp)
				str = str:gsub("\\", "/")
				str = str:gsub("root/", "")
								
				table.insert(paths, {path = str, type = type})

				item = hl.FolderFindNext(hl.PackageGetRoot(), item, "*", e.HL_FIND_ALL)
			end
			
			if item ~= nil then
				hl.StreamClose(pSubItem) 
			end
						
			self.paths = paths
			
			local exists = {}
			
			for k,v in pairs(paths) do
				exists[v.path] = v.type
			end
			
			self.exists = exists
		end

	hl.BindPackage(0)
	
	vpk.opened[path] = self
	self.vpk_path = path

	return self
end

function META:OnRemove()
	hl.BindPackage(self.id)
		hl.PackageClose()
		hl.DeletePackage(self.id)
--	hl.BindPackage(0)
end

function META:Find(path)
	local out = {}
	
	if path:sub(-1) == "/" then
		path = path .. "."
	end
	
	local dir = path:match("(.+)/")
		
	for k, v in pairs(self.paths) do
		if v.path:find(path) and v.path:match("(.+)/") == dir then
			table.insert(out, v.path:match(".+/(.+)") or v.path)
		end 
	end
	
	return out
end

function META:GetAttributes(path)
	local handle = self:Open(path)
		
	if self.exists[path:lower()] or handle then
		local base = lfs.attributes(self.vpk_path)
		return {
			mode = self.exists[path:lower()],
			size = handle and self:GetSize(handle) or 0,
			uid = 0,
			gid = 0,
			nlink = 0,
			access = base.access,
			modification = base.modification,
			change = base.change,
		}
	end
end

-- create a stream for the file for reading
local stream = ffi.new("void *[1]")
local size = ffi.new("unsigned int[1]")

function META:Open(path, mode)
	hl.BindPackage(self.id)
	mode = mode or e.HL_MODE_READ

	-- get the file we're looking for
	local file = hl.FolderGetItemByPath(hl.PackageGetRoot(), path, e.HL_FIND_ALL)
	
	if file ~= nil then
		hl.PackageCreateStream(file, stream)
		
		if stream[0] ~= nil then
			hl.StreamOpen(stream[0], mode)
		
			return {file = file, stream = stream[0]}
		end
	end
end

function META:Read(handle, bytes)
	hl.BindPackage(self.id)

	if not bytes then
		bytes = self:GetSize(handle)
	end
	
	local buffer = ffi.new("hlByte[?]", bytes)
	
	bytes = hl.StreamRead(handle.stream, buffer, bytes)
		
	return buffer, bytes
end

function META:GetSize(handle)
	hl.BindPackage(self.id)

	hl.ItemGetSize(handle.file, size) 
	
	return size[0]
end

function META:Seek(handle, offset, mode)
	hl.BindPackage(self.id)

	mode = mode or e.HL_SEEK_CURRENT
	return hl.StreamSeekEx(handle.stream, offset, mode)
end

function META:Close(handle)
	hl.StreamClose(handle.file) 
end

function META:Exists(path)
	return self.exists[path:lower()] ~= nil
end

_G.vpk = vpk