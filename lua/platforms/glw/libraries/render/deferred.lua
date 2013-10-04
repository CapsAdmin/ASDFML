local SHADER = {
	vertex = {
		uniform = {
			camera_matrix = "mat4",
			model_matrix = "mat4",
		},			
		attributes = {
			{pos = "vec2"},
			{uv = "vec2"},
		},
		source = "gl_Position = camera_matrix * model_matrix * vec4(pos, 0.0, 1.0);"
	},
	fragment = {
		uniform = {
			tex_diffuse = "sampler2D",
			tex_normal = "sampler2D",
			tex_position = "sampler2D", 
			tex_specular = "sampler2D",
			tex_depth = "sampler2D",
			cam_pos = "vec3",
		},  
		attributes = {
			uv = "vec2",
		},
		source = [[
			out vec4 out_color;

			void main ()
			{
				vec4 diffuse = texture2D(tex_diffuse, uv);
				vec4 normal = texture2D(tex_normal, uv);
				vec4 position = texture2D(tex_position, uv);
				vec4 light = texture2D(tex_specular, uv);
				vec4 depth = texture2D(tex_depth, uv);
	
				out_color = diffuse;
			}
		]]  
	}
}

function render.InitializeDeffered()

	render.gbuffer_config = {
		{
			name = "diffuse",
			attach = e.GL_COLOR_ATTACHMENT0,
			texture_format = {
				internal_format = e.GL_RGBA32F,
			}
		},
		{
			name = "normal",
			attach = e.GL_COLOR_ATTACHMENT1,
			texture_format = {
				internal_format = e.GL_RGBA32F,
			}
		},
		{
			name = "position",
			attach = e.GL_COLOR_ATTACHMENT2,
			texture_format = {
				internal_format = e.GL_RGBA32F,
			}
		},
		{
			name = "specular",
			attach = e.GL_COLOR_ATTACHMENT3,
			texture_format = {
				internal_format = e.GL_RGBA32F,
			}
		},
		{
			name = "light",
			attach = e.GL_COLOR_ATTACHMENT4,
			draw_manual = true,
			texture_format = {
				internal_format = e.GL_RGBA32F,
			}
		},
		{
			name = "depth",
			attach = e.GL_DEPTH_ATTACHMENT,
			draw_manual = true,
			texture_format = {
				internal_format = e.GL_DEPTH_COMPONENT32F,
				
			--	compare_mode = e.GL_COMPARE_R_TO_TEXTURE,
			--	compare_func = e.GL_EQUAL,					 
				[e.GL_DEPTH_TEXTURE_MODE] = e.GL_ALPHA,
				
			}
		}
	} 
	render.gbuffer = render.CreateFrameBuffer(render.w, render.h, render.gbuffer_config)  

	local shader = render.CreateSuperShader("deferred", SHADER)
	
	shader.model_matrix = render.GetModelMatrix
	shader.camera_matrix = render.GetCameraMatrix
	shader.cam_pos = render.GetCamPos
	
	shader.tex_diffuse = render.gbuffer:GetTexture("diffuse")
	shader.tex_position = render.gbuffer:GetTexture("position") 
	shader.tex_normal = render.gbuffer:GetTexture("normal")
	shader.tex_specular = render.gbuffer:GetTexture("specular")
	shader.tex_light = render.gbuffer:GetTexture("light")
	shader.tex_depth = render.gbuffer:GetTexture("depth")

	local screen_quad = shader:CreateVertexBuffer({
		{pos = {0, 0}, uv = {0, 1}},
		{pos = {0, 1}, uv = {0, 0}},
		{pos = {1, 1}, uv = {1, 0}},

		{pos = {1, 1}, uv = {1, 0}},
		{pos = {1, 0}, uv = {1, 1}},
		{pos = {0, 0}, uv = {0, 1}},
	})
	
	render.deferred_shader = shader
	render.deferred_screen_quad = screen_quad	
	--debug.logcalls(true)
end

local size = 3

function render.DrawDeffered(w, h)
	--render.Start3D()	
	
	--render.gbuffer:Begin("light", e.GL_TEXTURE4)
		
	--render.gbuffer.End()
	
	--render.Start2D()

	render.PushMatrix()
		surface.Scale(w, h)
		render.deferred_screen_quad:Draw()
	render.PopMatrix()
	
	if render.debug then
		w = w / size
		h = h / size
		
		local x = 0
		local y = 0
		
		for i, data in pairs(render.gbuffer_config) do
			surface.SetTexture(render.gbuffer:GetTexture(data.name))
			surface.DrawRect(x, y, w, h)
			
			surface.SetTextPos(x, y + 5)
			surface.DrawText(data.name)
			
			if i%size == 0 then
				y = y + h
				x = 0
			else
				x = x + w
			end
		end
	end
end

if render.deferred_shader then
	render.InitializeDeffered()
end
