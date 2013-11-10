surface = surface or {}

local surface = surface
local render = render
local math = math
local string = string
local table = table
local tostring = tostring
local tonumber = tonumber

surface.ft = surface.ft or {}
local ft = surface.ft

function surface.Initialize()
		
	surface.rectmesh = render.CreateMesh2D({
		{pos = {0, 0}, uv = {0, 1}, color = {1,1,1,1}},
		{pos = {0, 1}, uv = {0, 0}, color = {1,1,1,1}},
		{pos = {1, 1}, uv = {1, 0}, color = {1,1,1,1}},

		{pos = {1, 1}, uv = {1, 0}, color = {1,1,1,1}},
		{pos = {1, 0}, uv = {1, 1}, color = {1,1,1,1}},
		{pos = {0, 0}, uv = {0, 1}, color = {1,1,1,1}},
	})
		
	surface.white_texture = Texture(64,64)
	surface.white_texture:Fill(function() return 255, 255, 255, 255 end)
	surface.SetWhiteTexture()
	
	if not ft.ptr then
		local ptr = ffi.new("FT_Library[1]")  
		freetype.InitFreeType(ptr)
		ptr = ptr[0]
		ft.ptr = ptr	
	end
				 
	do
		local shader = render.CreateSuperShader("glyph", {
			fragment = {
				uniform = {
					smoothness = 0
				},
				source = [[
					out vec4 frag_color;

					void main()
					{								
						float mask = texture2D(texture, uv).a;

						frag_color.rgb = global_color.rgb;
						
						if (smoothness > 0)
						{
							mask = pow(mask, 0.75);
							mask *= smoothstep(0.25, 0.75 * smoothness, mask);
							mask = pow(mask, 1.25);
							mask *= smoothness * smoothness * smoothness;
						}
						
						frag_color.a = mask;
					}
				]],
			},
		}, "mesh_2d")
		
		local mesh = shader:CreateVertexBuffer({
			{pos = {0, 0}, uv = {0, 0}, color = {1,1,1,1}},
			{pos = {0, 1}, uv = {0, 1}, color = {1,1,1,1}},
			{pos = {1, 1}, uv = {1, 1}, color = {1,1,1,1}},

			{pos = {1, 1}, uv = {1, 1}, color = {1,1,1,1}},
			{pos = {1, 0}, uv = {1, 0}, color = {1,1,1,1}},
			{pos = {0, 0}, uv = {0, 0}, color = {1,1,1,1}},
		})
		
		mesh.model_matrix = render.GetModelMatrix
		mesh.camera_matrix = render.GetCameraMatrix	
		
		surface.fontmesh = mesh
		surface.fontshader = shader
	end

	surface.SetFont(surface.CreateFont("default"))	
	
	surface.ready = true
end

if surface.ready then
	surface.Initialize()
end

function surface.IsReady()
	return surface.ready == true
end

function surface.GetScreenSize()
	return render.w, render.h
end

function surface.Start()	
	render.Start2D()
end


local X, Y = 0, 0
local W, H = 0, 0
local R,G,B,A,A2 = 1,1,1,1,1

do -- fonts
	-- this might not be the best way to do it but it should do for now

	freetype.debug = true
		
	local DPI = 72
	
	ft.fonts = ft.fonts or {}
	ft.current_font = ft.current_font

	-- clear font data for reloading
	for k,v in pairs(ft.fonts) do
		v.glyphs = {}
		v.strings = {}
	end
	
	function surface.CreateFont(name, info)
		if not ft.ptr then return end
		
		info = info or {}

		info.path = info.path or "fonts/unifont.ttf"
		info.size = info.size or 14     
		info.spacing = info.spacing or 0
		
		info.border = math.pow2ceil(info.size) 
		info.border_2 = info.border / 2   
		 
		-- create a face from memory  
		local data, err = vfs.Read(info.path, "rb") 
		
		if not data then error("could not load font " .. info.path .. " : " .. err, 2) end
		
		local face = ffi.new("FT_Face[1]")   
		freetype.NewMemoryFace(ft.ptr, data, #data, 0, face)   
		face = face[0]	

		freetype.SetCharSize(face, 0, info.size * DPI, DPI, DPI)
		
		ft.fonts[name] = 
		{
			name = name, 
			face = face, 
			glyphs = {}, 
			strings = {},
			info = info,
			font_data = data, -- not doing this will make freetype crash because the data gets garbage collected
		}		
		
		return name
	end
	
	function surface.SetFont(name)
		ft.current_font = ft.fonts[name] or ft.fonts.default
	end

	function surface.GetFont()
		return ft.current_font and ft.current_font.name
	end
	
	local X, Y = 0,0
	local W, H = 1,1
	
	function surface.SetTextPos(x, y)
		X = x
		Y = y
	end
	
	function surface.SetTextScale(w, h)
		W = w
		H = h
	end
			
	function surface.DrawText(str)
		if not ft.ptr or not ft.current_font then return end
		
		str = tostring(str) 

		local face = ft.current_font.face
		local data = ft.current_font.strings[str]
		local info = ft.current_font.info 

		if not data then
			-- get the tallest character and use it as height
			local bbox = ffi.new("FT_BBox[1]")
			local glyph2 = ffi.new("FT_Glyph[1]")
			
			local i = freetype.GetCharIndex(face, ("|"):byte()) 
			freetype.LoadGlyph(face, i, 0)
			freetype.RenderGlyph(face.glyph, 0) 
			freetype.GetGlyph(face.glyph, glyph2)
			freetype.GlyphGetCBox(glyph2[0], 2, bbox)
			bbox = bbox[0]
			
			data = {chars = {}, h = face.glyph.bitmap.rows - bbox.yMin + 1, w = info.size}
			
			local w = 0
			
			for _, str in pairs(utf8.totable(str)) do
				local byte = utf8.byte(str)
				if byte == -1 then byte = str:byte() end
				
				if str == " " then	
					w = w + ft.current_font.info.size / 2
				elseif str == "\t" then
					w = w + ft.current_font.info.size * 2
				else				
					local glyph = ft.current_font.glyphs[str]
					
					if not glyph then
						local i = freetype.GetCharIndex(face, byte) 
						freetype.LoadGlyph(face, i, 0)
						freetype.RenderGlyph(face.glyph, 0) 
						
						local bitmap = face.glyph.bitmap 
						local m = face.glyph.metrics
						
						-- bboox
						local glyph2 = ffi.new("FT_Glyph[1]")
						freetype.GetGlyph(face.glyph, glyph2)
						
						local bbox = ffi.new("FT_BBox[1]")
						freetype.GlyphGetCBox(glyph2[0], 2, bbox)
						bbox = bbox[0]
						
						local x_min = bbox.xMin
						local x_max = bbox.xMax
						
						local y_min = bbox.yMin
						local y_max = bbox.yMax
						
						
						-- copy the data cause we call freetype.RenderGlyph the next frame
						local length = bitmap.width * bitmap.rows
						local buffer = ffi.new("unsigned char[?]", length)
						ffi.copy(buffer, bitmap.buffer, length)
						
						glyph = {
							buffer = buffer, 
							left = face.glyph.bitmap_left,
							top = face.glyph.bitmap_top,
				
							w = bitmap.width, 
							h = bitmap.rows,
							
							w2 = face.glyph.advance.x / DPI,
							w3 = face.glyph.linearHoriAdvance / DPI,
							
							bx = m.horiBearingX / DPI,
							by = m.horiBearingY / DPI,
							
							x_min = x_min,
							x_max = x_max,
							y_min = y_min,
							y_max = y_max,
							
							str = str,
						}
						
						ft.current_font.glyphs[str] = glyph
					end
					
					local char = {glyph = glyph}

					char.x = glyph.bx + w
					char.y = (info.size - glyph.y_max)
							
					if info.monospace then
						w = w + info.spacing
					else
						w = w + glyph.x_max + 1 + info.spacing
					end
					
					data.w = w

					table.insert(data.chars, char)
				end
			end
			
			local tex = Texture(math.floor(data.w + info.border), math.floor(data.h + info.border), buffer, {
				format = e.GL_ALPHA, 
				internal_format = e.GL_ALPHA8,
				stride = 1,
			})         
			
			tex:Clear()	  		
			for _, char in pairs(data.chars) do
				tex:Upload(
					char.glyph.buffer, 
					
					char.x + info.border_2,  
					char.y + info.border_2, 
					
					char.glyph.w, 
					char.glyph.h
				)       
			end
			
			data.tex = tex
						
			ft.current_font.strings[str] = data
		end 
		 
		if surface.debug then
			surface.SetWhiteTexture()
			surface.Color(1, 0, 0, 0.5)
			surface.DrawRect(X, Y, data.w * W, data.h * H)
			surface.Color(1,1,1,1,1)	
			
			surface.SetWhiteTexture()
			surface.Color(0, 1, 0, 0.6)  
			surface.DrawRect(X - info.border_2, Y - info.border_2, (data.w + info.border) * W, (data.h + info.border) * H)
			surface.Color(1,1,1,1,1)
		end
		
		surface.PushMatrix(X - info.border_2, Y - info.border_2, data.tex.w * W, data.tex.h * H) 
			surface.fontmesh.texture = data.tex
			surface.fontmesh.global_color = surface.rectmesh.global_color
			surface.fontmesh.smoothness = ft.current_font.info.smoothness 
			surface.fontmesh:Draw()
		surface.PopMatrix()
	end 
	
	function surface.GetTextSize(str)
		if not ft.current_font then
			return 0, 0
		end
	
		local data = ft.current_font.strings[str]
		
		if str == " " then
			return (ft.current_font.info.size / 2) * W, ft.current_font.info.size * H
		elseif str == "\t" then
			return (ft.current_font.info.size * 2) * W, (ft.current_font.info.size * H)
		elseif not data then
			surface.DrawText(str) 
			data = ft.current_font.strings[str]
			if not data then
				return 0, 0
			end
		end
	
		return data.w * W, data.h * H
	end
end

do -- orientation
	function surface.Translate(x, y)	
		render.Translate(math.ceil(x), math.ceil(y), 0)
	end
	
	function surface.Rotate(a)		
		render.Rotate(a, 0, 0, 1)
	end
	
	function surface.Scale(w, h)
		render.Scale(w, h or w, 0)
	end
		
	function surface.PushMatrix(x,y, w,h, a)
		render.PushMatrix()

		if x and y then surface.Translate(x, y, 0) end
		if w and h then surface.Scale(w, h, 1) end
		if a then surface.Rotate(a) end
	end
	
	function surface.PopMatrix()
		render.PopMatrix() 
	end
end

local COLOR = Color()

function surface.Color(r,g,b,a)
	R = r
	G = g
	B = b
	if a then
		A = a * A2
	end
	
	COLOR.r = R
	COLOR.g = G
	COLOR.b = B
	COLOR.a = A
	
	surface.rectmesh.global_color = COLOR
end

function surface.SetAlphaMultiplier(a)
	A2 = a
end

function surface.SetTexture(tex)
	tex = tex or surface.white_texture
	
	surface.rectmesh.texture = tex
	surface.bound_texture = tex
end

surface.SetWhiteTexture = surface.SetTexture

function surface.GetTexture()
	return surface.bound_texture or surface.white_texture
end

do
	local mesh_data = {
		{pos = {0, 0}, uv = {0, 1}, color = {1,1,1,1}},
		{pos = {0, 1}, uv = {0, 0}, color = {1,1,1,1}},
		{pos = {1, 1}, uv = {1, 0}, color = {1,1,1,1}},

		{pos = {1, 1}, uv = {1, 0}, color = {1,1,1,1}},
		{pos = {1, 0}, uv = {1, 1}, color = {1,1,1,1}},
		{pos = {0, 0}, uv = {0, 1}, color = {1,1,1,1}},
	}
	--[[{
		{pos = {0, 0}, uv = {xbl, ybl}, color = color_bottom_left},
		{pos = {0, 1}, uv = {xtl, ytl}, color = color_top_left},
		{pos = {1, 1}, uv = {xtr, ytr}, color = color_top_right},

		{pos = {1, 1}, uv = {xtr, ytr}, color = color_top_right},
		{pos = {1, 0}, uv = {xbr, ybr}, color = mesh_data[1].color},
		{pos = {0, 0}, uv = {xbl, ybl}, color = color_bottom_left},
	})]]
	
	-- sdasdasd
	
	local last_xtl = 0
	local last_ytl = 0
	local last_xtr = 1
	local last_ytr = 0
	
	local last_xbl = 0
	local last_ybl = 1
	local last_xbr = 1
	local last_ybr = 1
	
	local last_color_bottom_left = Color(1,1,1,1)
	local last_color_top_left = Color(1,1,1,1)
	local last_color_top_right = Color(1,1,1,1)
	local last_color_bottom_right = Color(1,1,1,1)
	
	local function update_vbo()
	
		if 
			last_xtl ~= mesh_data[2].uv[1] or
			last_ytl ~= mesh_data[2].uv[2] or
			last_xtr ~= mesh_data[4].uv[1] or
			last_ytr ~= mesh_data[4].uv[2] or
			
			last_xbl ~= mesh_data[1].uv[1] or
			last_ybl ~= mesh_data[2].uv[2] or
			last_xbr ~= mesh_data[5].uv[1] or
			last_ybr ~= mesh_data[5].uv[2] or
			
			last_color_bottom_left ~= mesh_data[1].color or
			last_color_top_left ~= mesh_data[2].color or
			last_color_top_right ~= mesh_data[3].color or
			last_color_bottom_right ~= mesh_data[5].color
		then
		
			surface.rectmesh:UpdateVertexBuffer(mesh_data)
			
			last_xtl = mesh_data[2].uv[1]
			last_ytl = mesh_data[2].uv[2]
			last_xtr = mesh_data[4].uv[1]
			last_ytr = mesh_data[4].uv[2]
			           
			last_xbl = mesh_data[1].uv[1]
			last_ybl = mesh_data[2].uv[2]
			last_xbr = mesh_data[5].uv[1]
			last_ybr = mesh_data[5].uv[2]
			
			last_color_bottom_left = mesh_data[1].color
			last_color_top_left = mesh_data[2].color
			last_color_top_right = mesh_data[3].color
			last_color_bottom_right = mesh_data[5].color	
		end		
	end

	function surface.SetRectUV(x,y, w,h, sx,sy)
		if not x then
			mesh_data[1].uv[1] = 0
			mesh_data[1].uv[2] = 1
			
			mesh_data[2].uv[1] = 0
			mesh_data[2].uv[2] = 0
			
			mesh_data[3].uv[1] = 1
			mesh_data[3].uv[2] = 0
			
			--
			
			mesh_data[4].uv = mesh_data[3].uv
			
			mesh_data[5].uv[1] = 1
			mesh_data[5].uv[2] = 1
			
			mesh_data[6].uv = mesh_data[1].uv	
		else			
			sx = sx or 1
			sy = sy or 1
			
			mesh_data[1].uv[1] = x / sx
			mesh_data[1].uv[2] = (y + h) / sy
			
			mesh_data[2].uv[1] = x / sx
			mesh_data[2].uv[2] = y / sy
			
			mesh_data[3].uv[1] = (x + w) / sx
			mesh_data[3].uv[2] = y / sy
			
			--
			
			mesh_data[4].uv = mesh_data[3].uv
			
			mesh_data[5].uv[1] = (x + w) / sx
			mesh_data[5].uv[2] = (y + h)
			
			mesh_data[6].uv = mesh_data[1].uv	
		end
		
				
		update_vbo()
	end

	local white_t = {1,1,1,1}

	function surface.SetRectColors(cbl, ctl, ctr, cbr)			
		if not cbl then
			for i = 1, 6 do
				mesh_data[i].color = white_t
			end
		else
			mesh_data[1].color = {cbl:Unpack()}
			mesh_data[2].color = {ctl:Unpack()}
			mesh_data[3].color = {ctr:Unpack()}
			mesh_data[4].color = mesh_data[3].color
			mesh_data[5].color = {cbr:Unpack()}
			mesh_data[6].color = mesh_data[1]
		end
		
		update_vbo()
	end
	
end

function surface.DrawRect(x,y, w,h, a, ox,oy)	
	render.PushMatrix()			
		surface.Translate(x, y)
		
		if a then
			surface.Rotate(a)
		end
		if ox then
			surface.Translate(-ox, -oy)
		end
				
		surface.Scale(w, h)
		surface.rectmesh:Draw()
	render.PopMatrix()
end

function surface.DrawLine(x1,y1, x2,y2, w, skip_tex, ...)
	
	w = w or 1
	
	if not skip_tex then 
		surface.SetWhiteTexture() 
	end
	
	local dx,dy = x2-x1, y2-y1
	local ang = math.atan2(dx, dy)
	local dst = math.sqrt((dx * dx) + (dy * dy))
		
	surface.DrawRect(x1, y1, w, dst, -math.deg(ang), ...)
end

function surface.StartClipping(x, y, w, h)
	y = -y + h
	render.ScissorRect(x, y, w, h)
	
end

function surface.EndClipping()
	render.ScissorRect()
end

function surface.WrapString(str, max_width)
	local lines = {}

	if not max_width or max_width == 0 then
		lines[1] = str
		return lines
	end
	
	local last_pos = 0
	local line_width = 0
	local found = false

	local space_pos

	for pos, char in pairs(str:utotable()) do
		local w, h = surface.GetTextSize(char)

		if char:find("%s") then
			space_pos = pos
		end

		if line_width + w >= max_width then

			if space_pos then
				table.insert(lines, str:usub(last_pos+1, space_pos))
				last_pos = space_pos
			else
				table.insert(lines, str:usub(last_pos+1, pos))
				last_pos = pos
			end

			line_width = 0
			found = true
			space_pos = nil
		else
			line_width = line_width + w
		end
	end

	if found then
		table.insert(lines, str:usub(last_pos+1, pos))
	else
		table.insert(lines, str)
	end

	return lines
end

do -- poly
	function surface.CreatePoly(size)
		local poly = {Type = "Poly"}
		
		size = size * 6
		local mesh = render.CreateMesh2D(size)
		
		local R,G,B,A = 1,1,1,1
		
		function poly:SetColor(r,g,b,a)
			R = r or 1
			G = g or 1
			B = b or 1
			A = a or 1
		end
		
		local U1, V1, U2, V2 = 0, 0, 1, 1
		
		function poly:SetUV(u1,v1,u2,v2)
			U1 = u1
			V1 = v1
			U2 = u2
			V2 = v2
		end
		
		local X, Y = 0, 0
		local R = 0
		
		function poly:SetVertex(i, x,y, u,v)
			if i > size or i < 0 then logf("i = %i size = %i", i, size)error("whaat") end
			
			if false and R ~= 0 then
				local t = glfw.GetTime()
				x = (X-x * math.cos(R)) - (Y-y * math.sin(R))
				y = (X-x * math.sin(R)) + (Y-y * math.cos(R))
				
				x = x + X
				y = y + Y
			end
			
			mesh.buffer[i].pos.A = x
			mesh.buffer[i].pos.B = y
			
			mesh.buffer[i].uv.A = u
			mesh.buffer[i].uv.B = v
			
			mesh.buffer[i].color.A = R
			mesh.buffer[i].color.B = G
			mesh.buffer[i].color.C = B
			mesh.buffer[i].color.D = A
		end
		
		function poly:SetRect(i, x,y,w,h, r, ox,oy)
		
			X = x
			Y = y
			R = r or 0
			OX = ox or 0
			OY = oy or 0
			
			i = i - 1
			i = i  * 6
			
			self:SetVertex(i + 0, x, y, U1, V1 + V2)
			self:SetVertex(i + 1, x, y + h, U1, V1)
			self:SetVertex(i + 2, x + w, y + h, U1 + U2, V1)

			self:SetVertex(i + 3, x + w, y + h, U1 + U2, V1)
			self:SetVertex(i + 4, x + w, y, U1 + U2, V1 + V2)
			self:SetVertex(i + 5, x, y, U1, V1 + V2)
		end
		
		poly.mesh = mesh
						
		return poly
	end

	function surface.DrawPoly(poly)
		poly.mesh:UpdateBuffer()
		poly.mesh.texture = surface.bound_texture
		poly.mesh.global_color = COLOR
		poly.mesh:Draw()
	end
end


return surface