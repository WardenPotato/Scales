require("scales")

local GENERIC_PREFIX, TOOL_INTERNAL_NAME, COMMAND_PREFIX, ENTITY_MODIFIER = scales.InternalGetPrefixes()

--#region Tool init variables
TOOL.Category = "Construction"
TOOL.Name = "#tool." .. TOOL_INTERNAL_NAME .. ".name"

TOOL.ClientConVar["server_physical_scale_x"] = "1.0"
TOOL.ClientConVar["server_physical_scale_y"] = "1.0"
TOOL.ClientConVar["server_physical_scale_z"] = "1.0"
TOOL.ClientConVar["scale_visual_with_physical"] = "1"
TOOL.ClientConVar["client_visual_scale_x"] = "1.0"
TOOL.ClientConVar["client_visual_scale_y"] = "1.0"
TOOL.ClientConVar["client_visual_scale_z"] = "1.0"
TOOL.ClientConVar["preserve_constraint_locations"] = "0"
TOOL.ClientConVar["disable_client_physics"] = "0"
--#endregion

if SERVER then
	local scales_clamp = CreateConVar(COMMAND_PREFIX .. "_clamp", "1", FCVAR_ARCHIVE + FCVAR_NOTIFY, "Force the Entity Resizer to clamp its values.")
	local scales_vertexlimit = CreateConVar(COMMAND_PREFIX .. "_convexvertexlimit", "500", FCVAR_ARCHIVE + FCVAR_NOTIFY, "Impose vertex limit to prevent lag.")
	local scales_propsonly = CreateConVar(COMMAND_PREFIX .. "_propsonly", "1", FCVAR_ARCHIVE + FCVAR_NOTIFY, "Only allow the tool to be used on prop_physics.")

	local function IsValidEntity(ent)
		return isentity(ent) and ent:IsValid()
	end

	--#region Sandbox tool functions
	function TOOL:GetClientBool(name)
		return tobool(self:GetClientInfo(name))
	end

	function TOOL:LeftClick(Trace)
		local ent = Trace.Entity

		if (not IsValidEntity(ent)) then return false end
		if (scales_propsonly:GetBool() and ent:GetClass() ~= "prop_physics") then return false end

		local server_physical_scale = Vector(self:GetClientNumber("server_physical_scale_x"), self:GetClientNumber("server_physical_scale_y"), self:GetClientNumber("server_physical_scale_z"))
		local client_visual_scale = Vector(self:GetClientNumber("client_visual_scale_x"), self:GetClientNumber("client_visual_scale_y"), self:GetClientNumber("client_visual_scale_z"))
		local scale_visual_with_physical = self:GetClientBool("scale_visual_with_physical")
		local disable_client_physics = self:GetClientBool("disable_client_physics")
		local clamp = scales_clamp:GetBool()
		local preserve_constraint_locations = self:GetClientBool("preserve_constraint_locations")
		local msg_callback = function(msg) self:GetOwner():ChatPrint(msg) end
		local vertex_limit = scales_vertexlimit:GetInt()

		return scales.ScaleEx(ent, server_physical_scale, client_visual_scale, scale_visual_with_physical, disable_client_physics, clamp, preserve_constraint_locations, msg_callback, vertex_limit)
	end

	function TOOL:RightClick(Trace)
		local ent = Trace.Entity

		if (not IsValidEntity(ent)) then return false end
		if (ent:IsRagdoll()) then return false end

		local preserve_constraint_locations = self:GetClientBool("preserve_constraint_locations")

		return scales.ResetScale(ent, preserve_constraint_locations)
	end
	--#endregion
end

if CLIENT then
	--#region Sandbox tool
	TOOL.Information = {
		{ name = "left" },
		{ name = "right" }
	}

	language.Add("tool." .. TOOL_INTERNAL_NAME .. ".name", "Scales Resizer")
	language.Add("tool." .. TOOL_INTERNAL_NAME .. ".desc", "Resizes entities")
	--	language.Add( "tool." .. TOOL_INTERNAL_NAME .. ".0", "Left click to resize. Right click to reset." )
	language.Add("tool." .. TOOL_INTERNAL_NAME .. ".left", "Set size")
	language.Add("tool." .. TOOL_INTERNAL_NAME .. ".right", "Fix size")

	language.Add("tool." .. TOOL_INTERNAL_NAME .. ".server_physical_scale_x", "Physical X Scale")
	language.Add("tool." .. TOOL_INTERNAL_NAME .. ".server_physical_scale_y", "Physical Y Scale")
	language.Add("tool." .. TOOL_INTERNAL_NAME .. ".server_physical_scale_z", "Physical Z Scale")
	language.Add("tool." .. TOOL_INTERNAL_NAME .. ".scale_visual_with_physical", "Scale Visual with Physical")
	language.Add("tool." .. TOOL_INTERNAL_NAME .. ".scale_visual_with_physical.help", "Use the above values to scale visually.")
	language.Add("tool." .. TOOL_INTERNAL_NAME .. ".client_visual_scale_x", "Visual X Scale")
	language.Add("tool." .. TOOL_INTERNAL_NAME .. ".client_visual_scale_y", "Visual Y Scale")
	language.Add("tool." .. TOOL_INTERNAL_NAME .. ".client_visual_scale_z", "Visual Z Scale")
	language.Add("tool." .. TOOL_INTERNAL_NAME .. ".preserve_constraint_locations", "Preserve Constraint Locations")
	language.Add("tool." .. TOOL_INTERNAL_NAME .. ".disable_client_physics", "Disable Client Physics")

	function TOOL.BuildCPanel(CPanel)
		CPanel:Help("#tool." .. TOOL_INTERNAL_NAME .. ".desc")

		local ctrl = vgui.Create("ControlPresets", CPanel)
		ctrl:SetPreset(COMMAND_PREFIX)
		local default = {
			scales_server_physical_scale_x = "1",
			scales_server_physical_scale_y = "1",
			scales_server_physical_scale_z = "1",
			scales_scale_visual_with_physical = "1",
			scales_client_visual_scale_x = "1",
			scales_client_visual_scale_y = "1",
			scales_client_visual_scale_z = "1",
			scales_preserve_constraint_locations = "0",
			scales_disable_client_physics = "0"
		}
		ctrl:AddOption("#preset.default", default)
		for k, v in pairs(default) do ctrl:AddConVar(k) end
		CPanel:AddPanel(ctrl)

		CPanel:NumSlider("#tool." .. TOOL_INTERNAL_NAME .. ".server_physical_scale_x", "scales_server_physical_scale_x", 0.1, 10, 2)
		CPanel:NumSlider("#tool." .. TOOL_INTERNAL_NAME .. ".server_physical_scale_y", "scales_server_physical_scale_y", 0.1, 10, 2)
		CPanel:NumSlider("#tool." .. TOOL_INTERNAL_NAME .. ".server_physical_scale_z", "scales_server_physical_scale_z", 0.1, 10, 2)

		CPanel:CheckBox("#tool." .. TOOL_INTERNAL_NAME .. ".scale_visual_with_physical", "scales_scale_visual_with_physical")

		CPanel:NumSlider("#tool." .. TOOL_INTERNAL_NAME .. ".client_visual_scale_x", "scales_client_visual_scale_x", 0.1, 10, 2)
		CPanel:NumSlider("#tool." .. TOOL_INTERNAL_NAME .. ".client_visual_scale_y", "scales_client_visual_scale_y", 0.1, 10, 2)
		CPanel:NumSlider("#tool." .. TOOL_INTERNAL_NAME .. ".client_visual_scale_z", "scales_client_visual_scale_z", 0.1, 10, 2)

		CPanel:CheckBox("#tool." .. TOOL_INTERNAL_NAME .. ".preserve_constraint_locations", "scales_preserve_constraint_locations")
		CPanel:CheckBox("#tool." .. TOOL_INTERNAL_NAME .. ".disable_client_physics", "scales_disable_client_physics")
	end
	--#endregion
end

if scales.GetShouldAutoRegisterOnSandbox() then
	scales.RegisterUndo()
	scales.RegisterDuplicator()
	scales.RegisterSaveRestore()
	scales.RegisterCleanup()
end