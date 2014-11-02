local gui2 = ... or _G.gui2
local S = gui2.skin.scale

do -- base property
	local PANEL = {}
	
	PANEL.Base = "text_button"
	PANEL.ClassName = "base_property"
	
	prototype.GetSet(PANEL, "DefaultValue")
		
	function PANEL:Initialize()
		prototype.GetRegistered(self.Type, "text_button").Initialize(self)
		 
		self:SetActiveStyle("property")
		self:SetInactiveStyle("property")
		self:SetHighlightOnMouseEnter(false)
		self:SetAlwaysReceiveMouseInput(true)
		self:SetClicksToActivate(2)
	end
	
	function PANEL:OnMouseInput(button, press)
		prototype.GetRegistered(self.Type, "button").OnMouseInput(self, button, press)
				
		if button == "button_1" and press then
			self:OnClick()
		end
	end
	
	function PANEL:OnPress()
		self:StartEditing()
	end
	
	function PANEL:StartEditing()
		if self.edit then return end
		
		local edit = gui2.CreatePanel("text_edit", self)
		
		edit:Dock("fill")
		edit:SetTextColor(Color(0, 1, 0))
		edit:SetText(self:GetEncodedValue())
		edit:SizeToText()
		edit.OnEnter = function() 
			self:StopEditing()
		end
		
		edit:RequestFocus()
		
		self.edit = edit
	end
	
	function PANEL:StopEditing()
		local edit = self.edit
		if edit then
			local str = edit:GetText()
			local val = self:Decode(str)
			
			str = self:Encode(val)
			
			self:SetText(str)
			edit:Remove()
			self:OnValueChanged(val)
			
			self.edit = nil
		end
	end
	
	function PANEL:SetValue(val)
		self:SetText(self:Encode(val))
		self.label:SetPosition(Vec2(S*2, S))
		self:OnValueChanged(val)
	end
	
	function PANEL:GetValue()
		return self:Decode(self:GetText())
	end
	
	function PANEL:GetEncodedValue()
		return self:Encode(self:GetValue() or self:GetDefaultValue())
	end
	
	function PANEL:Encode(var)
		return tostring(var)
	end
	
	function PANEL:Decode(str)
		return str
	end
	
	function PANEL:OnValueChanged(val)
	
	end
	
	function PANEL:OnClick()
	
	end
	
	gui2.RegisterPanel(PANEL)
end

do -- string
	local PANEL = {}
	
	PANEL.Base = "base_property"
	PANEL.ClassName = "string_property"
		
	function PANEL:Initialize()
		prototype.GetRegistered(self.Type, "base_property").Initialize(self)
		
		self:SetClicksToActivate(1)
	end
	
	gui2.RegisterPanel(PANEL)
end

do -- number
	local PANEL = {}
	
	PANEL.Base = "base_property"
	PANEL.ClassName = "number_property"
	
	function PANEL:Initialize()
		prototype.GetRegistered(self.Type, "base_property").Initialize(self)
		
		self:SetCursor("sizens")
	end
	
	function PANEL:Decode(str)
		return tonumber(str)
	end
	
	function PANEL:Encode(num)
		return tostring(num)
	end
	
	function PANEL:OnClick()
		self.drag_number = true
		self.base_value = nil
		self.drag_y_pos = nil
	end
	
	function PANEL:OnUpdate()
		if not self.drag_number then return end
		 
		if input.IsMouseDown("button_1") then			
			local pos = self:GetMousePosition()
			
			self.base_value = self.base_value or self:GetValue()
			
			if not self.base_value then return end
			
			self.drag_y_pos = self.drag_y_pos or pos.y
		
			local sens = 1
			
			if input.IsKeyDown("left_alt") then
				sens = sens / 10
			end
		
			local delta = ((self.drag_y_pos - pos.y) / 10) * sens
			local value = self.base_value + delta
			
			if input.IsKeyDown("left_control") then
				value = math.round(value)
			else
				value = math.round(value, 3)
			end
					
			self:SetValue(value)
		else
			self.drag_number = false 
		end
	end
	
	gui2.RegisterPanel(PANEL)
end

do -- vector
	local PANEL = {}
	
	PANEL.Base = "base_property"
	PANEL.ClassName = "vector_property"
	
	function PANEL:SetupNumbers(var, ...)
		for _, str in ipairs{...} do
			
		end
	end
		
	function PANEL:Decode(str)
		return tonumber(str)
	end
	
	function PANEL:Encode(num)
		return tostring(num)
	end
	
	gui2.RegisterPanel(PANEL)
end

local PANEL = {}

PANEL.ClassName = "properties"

PANEL.added_properties = {}

function PANEL:Initialize()
	self:SetStack(true)
	self:SetStackRight(false) 
	self:SetSizeStackToWidth(true)  
	self:SetNoDraw(true)
	
	self:AddEvent("PanelMouseInput")
end

function PANEL:AddGroup(name)
	local group = gui2.CreatePanel("collapsible_category", self)
	group:SetTitle(name)
	group.bar:SetInactiveStyle("gradient")
	group.bar:SetActiveStyle("gradient")
	local divider = gui2.CreatePanel("divider", group)
	divider:SetHideDivider(true)
	divider:Dock("fill")
	divider.OnDividerPositionChanged = function(_, pos)
		for i, group in ipairs(self:GetChildren()) do	
			if group.divider ~= divider then
				group.divider:SetDividerPosition(pos.x)
				group:Layout()
			end
		end
	end
	group.divider = divider
	
	local left = divider:SetLeft(gui2.CreatePanel("base"))
	left:SetStack(true)
	left:SetStackRight(false)
	left:SetSizeStackToWidth(true)
	left:Dock("fill")
	left:SetNoDraw(true)  
	group.left = left
	
	local right = divider:SetRight(gui2.CreatePanel("base"))
	right:SetStack(true)
	right:SetStackRight(false)
	right:SetSizeStackToWidth(true)
	right:Dock("fill")
	right:SetNoDraw(true)
	group.right = right
	 	
	self.current_group = group
end

function PANEL:AddProperty(key, default, callback, get_value)
	callback = callback or print
	get_value = get_value or function() return default end
	
	local t = type(default)
	
	if not self.current_group then
		self:AddGroup() 
	end 
	       
	local left = gui2.CreatePanel("base", self.current_group.left)
	left:SetStyle("property")
	
	local label = gui2.CreatePanel("text", left)
	label:SetText(key)
	label:SetPosition(Vec2(S*2, S))
	-- left:SetSize(label:GetSize()) 
	
	local right = gui2.CreatePanel("base", self.current_group.right) 
	right:SetMargin(Rect())
	
	if t == "boolean" then
		local panel = gui2.CreatePanel("button", right)
		panel:SetMode("toggle")
		panel:SetActiveStyle("check")
		panel:SetInactiveStyle("uncheck")
		panel.OnStateChanged = function(_, b) callback(b) end
		

	elseif prototype.GetRegistered("panel2", t .. "_property") then
		local panel = gui2.CreatePanel(t .. "_property", right)
					
		panel:SetValue(default)
		panel:SetDefaultValue(default)
		panel.GetValue = get_value
		panel.OnValueChanged = function(_, val) callback(val) end
		panel:Dock("fill")
		panel.key = key
		
		table.insert(self.added_properties, panel)
	else
		local panel = gui2.CreatePanel("base_property", right)
				
		function panel:Decode(str)
			local val = serializer.Decode("luadata", str)[1]
			
			if type(val) ~= t then
				val = default
			end
			
			return val
		end
		
		function panel:Encode(val)
			return serializer.Encode("luadata", val)
		end
				
		panel:SetValue(default)
		panel:SetDefaultValue(default)
		panel.GetValue = get_value
		panel.OnValueChanged = function(_, val) callback(val) end
		panel:Dock("fill")
		
		table.insert(self.added_properties, panel)
	end
	
	left:SetHeight(15)	
	right:SetHeight(left:GetHeight())
	
	self.left_max_width = math.max((self.left_max_width or 0), label:GetWidth() + label:GetX()*2)
	self.right_max_width = math.max((self.right_max_width or 0), right:GetWidth())
		
	self:Layout()
end

function PANEL:OnLayout()
	if not self.left_max_width then return end
		
	for i, group in ipairs(self:GetChildren()) do		
		group:SetHeight(group.left:GetSizeOfChildren().h + S*10)
		group:SetWidth(math.max(self:GetWidth(), self.left_max_width + self.right_max_width))
		group.divider:SetWidth(self.left_max_width + self.right_max_width) 
		 group.divider:SetDividerPosition(self.left_max_width) 
	end
end

function PANEL:OnPanelMouseInput(panel, button, press)
	if press and button == "button_1" and panel.ClassName ~= "text_edit" then
		for i, right in ipairs(self.added_properties) do
			if panel ~= right then
				right:StopEditing()
			end
		end
	end
end

function PANEL:AddPropertiesFromObject(obj)
	for k, v in pairs(getmetatable(obj) or obj) do
		if type(v) == "function" and k:sub(0, 3) == "Get" then
			local field = k:sub(4)
			
			local get = v 
			local set = obj["Set" .. field]
			local def = get(obj)
			
			if get and set and obj[field] and type(def) ~= "table" then
				self:AddProperty(field:gsub("%u", " %1"):lower():sub(2), def, function(val)
					if not obj:IsValid() then return end
					
					set(obj, val)
				end, function() 
					if not obj:IsValid() then return end
					
					return get(obj)
				end)
			end
		end
	end
end

gui2.RegisterPanel(PANEL) 
 
if RELOAD then
	local frame = utility.RemoveOldObject(gui2.CreatePanel("frame")) 
	frame:SetSize(Vec2(300, gui2.world:GetHeight()))
	
	local div = gui2.CreatePanel("divider", frame)
	div:Dock("fill")
	
	local tree = div:SetTop(gui2.CreatePanel("tree"))
	
	local function fill(entities, node)
		for key, ent in pairs(entities) do
			local node = node:AddNode(ent.config)
			node.ent = ent
			--node:SetIcon(Texture("textures/" .. icons[val.self.ClassName]))
			fill(ent:GetChildren(), node)
		end  
	end 
	
	fill(entities.GetAll(), tree)
	
	local scroll = div:SetBottom(gui2.CreatePanel("scroll"))
	
	local properties
	
	tree.OnNodeSelect = function(_, node)
		gui2.RemovePanel(properties)
		
		properties = gui2.CreatePanel("properties")
		properties:SetStretchToPanelWidth(frame)
		
		for k, v in pairs(node.ent:GetComponents()) do
			for k,v in pairs(v) do
				properties:AddGroup(v.ClassName)
				properties:AddPropertiesFromObject(v)
			end
		end
		
		scroll:SetPanel(properties) 
	end
	
	
	div:SetDividerPosition(gui2.world:GetHeight()/2) 
	
	tree:SelectNode(tree:GetChildren()[1])  
end