﻿local META = {}

META.Type = "font"
META.ClassName = "base"

prototype.GetSet(META, "Path", "")
prototype.GetSet(META, "Padding", 0)
prototype.IsSet(META, "Spacing", 1)
prototype.IsSet(META, "Size", 12)
prototype.IsSet(META, "Scale", Vec2(1,1))
prototype.GetSet(META, "Filtering", "linear")
prototype.GetSet(META, "ShadingInfo")
prototype.GetSet(META, "FallbackFonts")
prototype.IsSet(META, "Monospace", false)
prototype.IsSet(META, "Ready", false)
prototype.GetSet(META, "LoadSpeed", 10)
prototype.GetSet(META, "Shadow", 0)
prototype.GetSet(META, "ShadowColor", Color(0,0,0,1))

function META:GetGlyphData(code)
	error("not implemented")
end

function META:CreateTextureAtlas()
	self.texture_atlas = render.CreateTextureAtlas(512, 512, self.Filtering)
	self.texture_atlas:SetPadding(self.Padding)

	for code in pairs(self.chars) do
		self.chars[code] = nil
		self:LoadGlyph(code)
	end

	self.texture_atlas:Build()
end

function META:Shade(source, vars, blend_mode)
	if source then
		for _, tex in ipairs(self:GetTextures()) do
			tex:Shade(source, vars, blend_mode)
		end
	elseif self.ShadingInfo then
		self:CreateTextureAtlas()

		for _, info in ipairs(self.ShadingInfo) do
			for _, tex in ipairs(self.texture_atlas:GetTextures()) do
				tex:Shade(info.source, info.vars, info.blend_mode)
			end
		end
	end
end

function META:Rebuild()
	if self.ShadingInfo then
		self:Shade()
	else
		self.texture_atlas:Build()
	end
end

function META:LoadGlyph(code)
	if self.chars[code] then return end

	local buffer, char = self:GetGlyphData(code)

	if not buffer and self.FallbackFonts then
		for _, font in ipairs(self.FallbackFonts) do
			buffer, char = font:GetGlyphData(code)
			if buffer then break end
		end
	end

	if buffer then
		self.texture_atlas:Insert(code, {
			w = char.w,
			h = char.h,
			buffer = buffer,
			flip_y = true,
		})

		self.chars[code] = char
	end
end

function META:DrawString(str, x, y, w)
	if not self.Ready then return end

	if str == nil then str = "nil" end

	self.string_cache = self.string_cache or {}

	if not self.string_cache[str] then
		self.total_strings_stored = self.total_strings_stored or 0

		if self.total_strings_stored > 10000 then
			logf("fonts warning: string cache for %s is above 10000, flushing cache\n", self)
			table.clear(self.string_cache)
			self.total_strings_stored = 0
		end

		self.string_cache[str] = self:CompileString({tostring(str)})
		self.total_strings_stored = self.total_strings_stored + 1
	end

	self.string_cache[str]:Draw(x, y, w)

	if fonts.debug_font_size then
		render2d.SetColor(1,0,0,0.25)
		render2d.SetTexture()
		render2d.DrawRect(x, y, gfx.GetTextSize(str))
	end
end

function META:SetPolyChar(poly, i, x, y, char)
	local ch = self.chars[char]

	if ch then
		local x_,y_, w,h, sx,sy = self.texture_atlas:GetUV(char)
		poly:SetUV(x_,y_, w,h, sx,sy)

		x = x - self.Padding / 2
		y = y - self.Padding * 2

		x = x * self.Scale.x
		y = y * self.Scale.y

		y = y - ch.bitmap_top + self.Size + (0.5 * self.Scale.y)

		poly:SetRect(i, x, y, w * self.Scale.x, h * self.Scale.y)
	end
end

function META:CompileString(data)
	local vertex_count = 0

	do
		for _, str in ipairs(data) do
			if type(str) == "string" then
				local rebuild = false
				vertex_count = vertex_count + (utf8.length(str) * 6)
				for i = 1, utf8.length(str) do
					local char = utf8.sub(str, i,i)
					local ch = self.chars[char]
					if not ch then
						self:LoadGlyph(char)
						rebuild = true
					end
				end

				if rebuild then
					self:Rebuild()
				end
			end
		end
	end

	local poly = gfx.CreatePolygon2D(vertex_count)
	local width_info = {}
	local out = {}

	local max_width = 0
	local X, Y = 0, 0
	local i = 1
	local last_tex

	for _, str in ipairs(data) do
		if type(str) ~= "string" then
			if typex(str) == "vec2" then
				X = str.x
				Y = str.y
			else
				poly:SetColor(str:Unpack())
			end
		else
			for str_i = 1, utf8.length(str) do
				local char = utf8.sub(str, str_i,str_i)
				local ch = self.chars[char]

				if char == "\n" then
					X = 0
					Y = Y + self.Size
				elseif char == "\t" then
					local ch = self.chars[" "]

					if ch then
						if self.Monospace then
							X = X + self.Spacing * 4
						else
							X = X + ((ch.x_advance + self.Spacing) * self.Scale.x) * 4
						end
					else
						X = X + self.Size * 4
					end
				elseif not ch and char == " " then
					local ch = self.chars[" "]

					if ch then
						if self.Monospace then
							X = X + self.Spacing
						else
							X = X + (ch.x_advance + self.Spacing) * self.Scale.x
						end
					else
						X = X + self.Size
					end
				elseif ch then
					local texture = self.texture_atlas:GetPageTexture(char)

					if texture ~= last_tex then
						table.insert(out, {poly = poly, texture = texture})
						last_tex = texture
					end

					self:SetPolyChar(poly, i, X, Y, char)

					if self.Monospace then
						X = X + self.Spacing
					else
						X = X + ch.x_advance + self.Spacing
					end

					width_info[i] = X

					i = i + 1
				end
				max_width = math.max(max_width, X)
			end
		end
	end

	local string = {}

	local width_cache = utility.CreateWeakTable()

	function string:Draw(x, y, w)
		if w and not width_cache[w] then
			for i, x in ipairs(width_info) do
				if x > w then
					width_cache[w] = (i - 1) * 6
					break
				end
			end
		end

		render2d.PushMatrix(x, y)
		for _, v in ipairs(out) do
			render2d.SetTexture(v.texture)
			v.poly:Draw(width_cache[w])
		end
		render2d.PopMatrix()
	end

	return string, max_width, Y
end

function META:GetTextSize(str)
	if not self.Ready then return 0,0 end

	str = tostring(str)

	local X, Y = 0, self.Size

	local rebuild = false
	local length = utf8.length(str)

	for i = 1, length do
		local char = utf8.sub(str, i,i)
		local ch = self.chars[char]
		if not ch then
			self:LoadGlyph(char)
			rebuild = true
		end
	end

	if rebuild then
		self:Rebuild()
	end

	for i = 1, length do
		local char = utf8.sub(str, i,i)
		local ch = self.chars[char]
		if char == "\n" then
			Y = Y + self.Size * self.Scale.y
		elseif char == "\t" then
			local ch = self.chars[" "]
			if ch then
				if self.Monospace then
					X = X + self.Spacing * 4
				else
					X = X + ((ch.x_advance + self.Spacing) * self.Scale.x) * 4
				end
			else
				X = X + self.Size * 4
			end
		elseif not ch and char == " " then
			local ch = self.chars[" "]

			if ch then
				if self.Monospace then
					X = X + self.Spacing
				else
					X = X + (ch.x_advance + self.Spacing) * self.Scale.x
				end
			else
				X = X + self.Size
			end
		elseif ch then
			if self.Monospace then
				X = X + self.Spacing
			else
				X = X + (ch.x_advance + self.Spacing) * self.Scale.x
			end
		end
	end
	return X, Y
end

function META:WrapString(str, max_width, max_word_length)
	max_word_length = max_word_length or 15
	local tbl = {}
	local tbl_i = 1
	local start_pos = 1
	local end_pos = 1

	local str_tbl = utf8.totable(str)

	for i = 1, #str_tbl do
		end_pos = end_pos + 1
		if self:GetTextSize(str:usub(start_pos, end_pos)) > max_width then
			local n = str_tbl[end_pos]

			for i = 1, max_word_length do
				if n == " " or n == "," or n == "." or n == "\n" then
					break
				else
					end_pos = end_pos - 1
					n = str_tbl[end_pos]
				end
			end

			tbl[tbl_i] = str:usub(start_pos, end_pos):trim()
			tbl_i = tbl_i + 1
			start_pos = end_pos + 1
		end
	end
	tbl[tbl_i] = str:usub(start_pos, end_pos)
	tbl_i = tbl_i + 1
	return table.concat(tbl,"\n")
end

function META:OnLoad()

end

prototype.Register(META)

if RELOAD then
	for _, v in pairs(fonts.registered_fonts) do
		fonts.RegisterFont(v)
	end
	for _, v in pairs(prototype.GetCreated()) do
		if v.Type == "font" then
			v.string_cache = {}
			v.total_strings_stored = 0
			v:CreateTextureAtlas()
			v:Rebuild()
		end
	end
end