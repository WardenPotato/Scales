--By: Warden Potato (STEAM_0:0:81170861, STEAM_0:0:56280098) of the Zombies.Zone community
--Based on: Prop Resizer addon

AddCSLuaFile()

local version = 1.1
MsgN("Loading Scales: " .. version)

--Global definitions we're gonna import into this module
local MOVETYPE_NONE = MOVETYPE_NONE
local SOLID_VPHYSICS = SOLID_VPHYSICS
local Vector = Vector
local TypeID = TypeID
local scripted_ents = scripted_ents
local SERVER = SERVER
local CLIENT = CLIENT
local FindMetaTable = FindMetaTable
local isentity = isentity
local ents = ents
local pairs = pairs
local istable = istable
local isvector = isvector
local isstring = isstring
local isfunction = isfunction
local isnumber = isnumber
local unpack = unpack
local Model = Model
local net = net
local util = util
local math = math
local table = table
local Matrix = Matrix
local hook = hook
local tostring = tostring
local saverestore = saverestore
local duplicator = duplicator
local undo = undo
local cleanup = cleanup
local TYPE_PHYSOBJ = TYPE_PHYSOBJ

module("scales")

--#region Configuration
--Stands for Zombies.Zone(my community) Scales, should be unique enough to not conflict with other peoples stuff
local GENERIC_PREFIX = "zz_scales_"
local TOOL_INTERNAL_NAME = "scales"
local COMMAND_PREFIX = "scales"
local ENTITY_MODIFIER = "scales"

function InternalGetPrefixes()
	return GENERIC_PREFIX, TOOL_INTERNAL_NAME, COMMAND_PREFIX, ENTITY_MODIFIER
end

-- Put any models that crash the server, or shouldn't scale physics here.
local badPhysicsModels = {
	["models/props_manor/fireplace_logs.mdl"] = true,
}
--#endregion

--#region Shadow entity definition
local ENT = {}

ENT.Type = "anim"

ENT.Spawnable = false
ENT.DisableDuplicator = true
--#endregion

--#region Util functions
local RESET = Vector(1, 1, 1)
local EMPTY = Vector(0, 0, 0)

local function IsValidEntity(ent)
	return isentity(ent) and ent:IsValid()
end

local function IsValidPhysicsObject(physobj)
	return (TypeID(physobj) == TYPE_PHYSOBJ) and physobj:IsValid()
end

local function FindSizeHandler(ent)
	for k, handler in pairs(ents.FindByClass(GENERIC_PREFIX .. "sizehandler")) do
		if (handler:GetParent() == ent) then return handler end
	end
end
--#endregion

--Resize physics
local function ResizePhysics(ent, scale, vertex_limit)
	ent:PhysicsInit(SOLID_VPHYSICS)

	local physobj = ent:GetPhysicsObject()

	if (not IsValidPhysicsObject(physobj)) then return false end

	local physmesh = physobj:GetMeshConvexes()

	if (not istable(physmesh)) or (#physmesh < 1) then return false end

	for convexkey, convex in pairs(physmesh) do
		if isnumber(vertex_limit) and #convex > vertex_limit then return false end

		for poskey, postab in pairs(convex) do
			convex[poskey] = postab.pos * scale
		end
	end

	ent:PhysicsInitMultiConvex(physmesh)

	ent:EnableCustomCollisions(true)

	return IsValidPhysicsObject(ent:GetPhysicsObject())
end

local InternalScale, InternalResetScale = function() end, function() end

local IsUndoRegistered, IsDuplicatorRegistered, IsSaveRestoreRegistered, IsCleanupRegistered = false, false, false, false
local InternalRegisterUndo, InternalRegisterDuplicator, InternalRegisterSaveRestore, InternalRegisterCleanup = function() end, function() end, function() end, function() end
if (SERVER) then
	--#region Meta additions
	local meta = FindMetaTable("Entity")

	local o_StartMotionController = meta.StartMotionController
	meta.StartMotionController = function(ent)
		o_StartMotionController(ent)

		ent.IsMotionControlled = true
	end

	local o_StopMotionController = meta.StopMotionController
	meta.StopMotionController = function(ent)
		o_StopMotionController(ent)

		ent.IsMotionControlled = nil
	end
	--#endregion

	--#region Util functions
	local function HasValidPhysics(ent)
		return (ent:GetSolid() == SOLID_VPHYSICS) and (ent:GetPhysicsObjectCount() == 1)
	end

	local ConstraintData = {}

	local function ForgetConstraint(ent, RConstraint)
		local Constraints = ent.Constraints

		if (Constraints) then
			local NewTab = {}

			for k, Constraint in pairs(Constraints) do
				if (Constraint ~= RConstraint) then
					table.insert(NewTab, Constraint)
				end
			end

			ent.Constraints = NewTab
		end
	end

	local function SafeInsert(t, k, v)
		if (v) then
			t[k] = v
		else
			t[k] = false
		end
	end

	local function GetConstraintVals(ent, Constraint, Type)
		for Arg, Val in pairs(Constraint:GetTable()) do
			if ((string.sub(Arg, 1, 3) == "Ent") and IsValidEntity(Val) and (Val ~= ent)) then
				ForgetConstraint(Val, Constraint)
			end
		end

		local Factory = duplicator.ConstraintType[Type]

		local ConstraintVals = {}

		for Key, Arg in pairs(Factory.Args) do
			SafeInsert(ConstraintVals, Key, Constraint[Arg])
		end

		ConstraintData[Constraint] = { Factory.Func, ConstraintVals }

		Constraint:Remove()
	end

	local function GetAndResizeConstraintVals(ent, Constraint, Type, scale)
		local LPos = {}

		for Arg, Val in pairs(Constraint:GetTable()) do
			if (string.sub(Arg, 1, 3) == "Ent") then
				if (Val == ent) then
					table.insert(LPos, "LPos" .. string.sub(Arg, 4))
				elseif (IsValidEntity(Val)) then
					ForgetConstraint(Val, Constraint)
				end
			end
		end

		local Factory = duplicator.ConstraintType[Type]

		local ConstraintVals = {}

		for Key, Arg in pairs(Factory.Args) do
			if (table.HasValue(LPos, Arg)) then
				local Val = Constraint[Arg]

				if (isvector(Val)) then
					ConstraintVals[Key] = Val * scale
				else
					SafeInsert(ConstraintVals, Key, Val)
				end
			else
				SafeInsert(ConstraintVals, Key, Constraint[Arg])
			end
		end

		ConstraintData[Constraint] = { Factory.Func, ConstraintVals }

		Constraint:Remove()
	end

	local function StoreConstraintData(ent)
		local Constraints = ent.Constraints

		if (Constraints) then
			for Key, Constraint in pairs(Constraints) do
				if (IsValidEntity(Constraint) and (ConstraintData[Constraint] == nil)) then
					local Type = Constraint.Type

					if (Type) then
						GetConstraintVals(ent, Constraint, Type)
					end
				end

				Constraints[Key] = nil
			end
		end
	end

	local function ResizeAndStoreConstraintData(ent, scale, oldscale)
		local Constraints = ent.Constraints

		if (Constraints) then
			for Key, Constraint in pairs(Constraints) do
				if (IsValidEntity(Constraint) and (ConstraintData[Constraint] == nil)) then
					local Type = Constraint.Type

					if (Type) then
						if (Type == "Axis") then
							GetConstraintVals(ent, Constraint, Type)
						else
							GetAndResizeConstraintVals(ent, Constraint, Type, Vector(scale.x / oldscale.x, scale.y / oldscale.y, scale.z / oldscale.z))
						end
					end
				end

				Constraints[Key] = nil
			end
		end
	end

	local function ApplyConstraintData()
		for OldConstraint, Factory in pairs(ConstraintData) do
			local NewConstraint = Factory[1](unpack(Factory[2]))

			if (IsValidEntity(NewConstraint)) then
				if IsUndoRegistered then undo.ReplaceEntity(OldConstraint, NewConstraint) end
				if IsCleanupRegistered then cleanup.ReplaceEntity(OldConstraint, NewConstraint) end
			end

			ConstraintData[OldConstraint] = nil
		end
	end

	local PhysicsData = {}

	local function StorePhysicsData(physobj)
		PhysicsData[1] = physobj:IsGravityEnabled()
		PhysicsData[2] = physobj:GetMaterial()
		PhysicsData[3] = physobj:IsCollisionEnabled()
		PhysicsData[4] = physobj:IsDragEnabled()
		PhysicsData[5] = physobj:GetVelocity()
		PhysicsData[6] = physobj:GetAngleVelocity()
		PhysicsData[7] = physobj:IsMotionEnabled()
	end

	local function ApplyPhysicsData(physobj)
		physobj:EnableGravity(PhysicsData[1])
		physobj:SetMaterial(PhysicsData[2])
		physobj:EnableCollisions(PhysicsData[3])
		physobj:EnableDrag(PhysicsData[4])
		physobj:SetVelocity(PhysicsData[5])
		physobj:AddAngleVelocity(PhysicsData[6] - physobj:GetAngleVelocity())
		physobj:EnableMotion(PhysicsData[7])
	end

	local models_error = Model("models/error.mdl")

	local function CreateSizeHandler(ent)
		local handler = ents.Create(GENERIC_PREFIX .. "sizehandler")
		handler:SetPos(ent:GetPos())
		handler:SetAngles(ent:GetAngles())
		handler:SetModel(models_error)
		handler:SetNoDraw(true)
		handler:DrawShadow(false)
		handler:SetNotSolid(true)
		handler:SetMoveType(MOVETYPE_NONE)
		handler:SetParent(ent)
		handler:SetTransmitWithParent(true)

		handler:Spawn()

		return handler
	end

	local function GetSizeHandler(ent)
		local handler = FindSizeHandler(ent)

		if (IsValidEntity(handler)) then return handler end

		return CreateSizeHandler(ent)
	end

	local ResizedEntities = {}

	local function CreateSizeData(ent, physobj)
		for k, v in pairs(ResizedEntities) do if (not IsValidEntity(k)) then ResizedEntities[k] = nil end end

		local sizedata = {}

		sizedata[1] = Vector(1, 1, 1)

		sizedata[2], sizedata[3] = ent:GetCollisionBounds()
		sizedata[4] = physobj:GetMass()

		ResizedEntities[ent] = sizedata

		return sizedata
	end

	util.AddNetworkString(COMMAND_PREFIX .. "_set_physical_size")
	util.AddNetworkString(COMMAND_PREFIX .. "_fix_physical_size")

	local function InternalSetPhysicalSize(ent, scale, size_handler, was_resized, preserve_constraint_locations, disable_client_physics, msg_callback, vertex_limit)
		if (HasValidPhysics(ent)) then
			local physobj = ent:GetPhysicsObject()

			if (IsValidPhysicsObject(physobj)) then
				local sizedata = ResizedEntities[ent] or CreateSizeData(ent, physobj)

				if (preserve_constraint_locations) then
					StoreConstraintData(ent)
				else
					ResizeAndStoreConstraintData(ent, scale, sizedata[1])
				end
				StorePhysicsData(physobj)

				local success = ResizePhysics(ent, scale, vertex_limit)
				if not success then
					if isfunction(msg_callback) then
						msg_callback("Entity Resizer: Can not scale physics, too complex!")
					end
				end

				if (disable_client_physics) then
					net.Start(COMMAND_PREFIX .. "_fix_physical_size")
						net.WriteEntity(ent)
					net.Broadcast()

					if (was_resized) then
						size_handler:SetActualPhysicsScale(tostring(RESET))
					end
				else
					if (was_resized) then
						net.Start(COMMAND_PREFIX .. "_set_physical_size")
							net.WriteEntity(ent)
							net.WriteString(tostring(scale))
						net.Broadcast()
					else
						size_handler = CreateSizeHandler(ent)
					end

					size_handler:SetActualPhysicsScale(tostring(scale))
				end

				ent:SetCollisionBounds(sizedata[2] * scale, sizedata[3] * scale)

				if (success) then
					physobj = ent:GetPhysicsObject()

					physobj:SetMass(math.Clamp(sizedata[4] * scale.x * scale.y * scale.z, 0.1, 50000))
					physobj:SetDamping(0, 0)

					ApplyConstraintData()
					ApplyPhysicsData(physobj)

					physobj:Wake()

					if (ent.IsMotionControlled) then o_StartMotionController(ent) end
				else
					ApplyConstraintData()
				end

				sizedata[1]:Set(scale)
			end
		end
	end

	local function InternalFixPhysicalSize(ent, size_handler, was_resized, preserve_constraint_locations)
		if (HasValidPhysics(ent)) then
			local physobj = ent:GetPhysicsObject()

			if (IsValidPhysicsObject(physobj)) then
				local sizedata = ResizedEntities[ent]

				if (not sizedata) then return end

				if (preserve_constraint_locations) then
					StoreConstraintData(ent)
				else
					ResizeAndStoreConstraintData(ent, RESET, sizedata[1])
				end
				StorePhysicsData(physobj)

				ent:EnableCustomCollisions(false)
				ent:PhysicsInit(SOLID_VPHYSICS)

				net.Start(COMMAND_PREFIX .. "_fix_physical_size")
					net.WriteEntity(ent)
				net.Broadcast()

				if (was_resized) then
					size_handler:SetActualPhysicsScale(tostring(RESET))
				end

				ent:SetCollisionBounds(sizedata[2], sizedata[3])

				physobj = ent:GetPhysicsObject()

				if (IsValidPhysicsObject(physobj)) then
					physobj:SetMass(sizedata[4])

					ApplyConstraintData()
					ApplyPhysicsData(physobj)

					physobj:Wake()

					if (ent.IsMotionControlled) then o_StartMotionController(ent) end
				else
					ApplyConstraintData()
				end

				ResizedEntities[ent] = nil
			end
		end
	end

	util.AddNetworkString(COMMAND_PREFIX .. "_set_visual_size")
	util.AddNetworkString(COMMAND_PREFIX .. "_fix_visual_size")

	local function InternalSetVisualSize(ent, scale, was_resized)
		if (not was_resized) then return end

		net.Start(COMMAND_PREFIX .. "_set_visual_size")
			net.WriteEntity(ent)
			net.WriteString(tostring(scale))
		net.Broadcast()
	end

	local function InternalFixVisualSize(ent)
		net.Start(COMMAND_PREFIX .. "_fix_visual_size")
			net.WriteEntity(ent)
		net.Broadcast()
	end



	local function ClampVal(obb, scale)
		scale.x = math.Clamp(obb.x * scale.x, 0.1, 5000) / obb.x
		scale.y = math.Clamp(obb.y * scale.y, 0.1, 5000) / obb.y
		scale.z = math.Clamp(obb.z * scale.z, 0.1, 5000) / obb.z
	end

	function Scale(ent, server_physical_scale, client_visual_scale, scale_visual_with_physical, disable_client_physics, clamp, preserve_constraint_locations, msg_callback, vertex_limit)
		local obb = ent.EntityResizerOriginalOBB
		if not obb then
			obb = ent:OBBMaxs() - ent:OBBMins(); ent.EntityResizerOriginalOBB = obb
		end

		if (scale_visual_with_physical) then
			if (clamp) then
				ClampVal(obb, server_physical_scale)
			end
		else
			if (clamp) then
				ClampVal(obb, server_physical_scale)
				ClampVal(obb, client_visual_scale)
			end
		end

		-- If it's a bad physics model, we simply just let the scale be at 1
		if badPhysicsModels[ent:GetModel()] then
			server_physical_scale = Vector(1, 1, 1)
			if isfunction(msg_callback) then
				msg_callback("Entity Resizer: Can not scale physics, too complex!")
			end
		end

		local size_handler = FindSizeHandler(ent)
		local was_resized = IsValidEntity(size_handler)

		if (server_physical_scale == RESET) then
			InternalFixPhysicalSize(ent, preserve_constraint_locations)

			if (client_visual_scale == RESET) then
				InternalFixVisualSize(ent)

				if (was_resized) then size_handler:Remove() end

				if IsDuplicatorRegistered then duplicator.ClearEntityModifier(ent, ENTITY_MODIFIER) end

				return true
			else
				InternalSetVisualSize(ent, client_visual_scale, was_resized)
			end
		else
			InternalSetPhysicalSize(ent, server_physical_scale, size_handler, was_resized, preserve_constraint_locations, disable_client_physics, msg_callback, vertex_limit)

			if (client_visual_scale == RESET) then
				InternalFixVisualSize(ent)
			else
				InternalSetVisualSize(ent, client_visual_scale, was_resized)
			end
		end

		if (not IsValidEntity(size_handler)) then size_handler = CreateSizeHandler(ent) end
		size_handler:SetVisualScale(tostring(client_visual_scale))

		if IsDuplicatorRegistered then
			duplicator.StoreEntityModifier(ent, ENTITY_MODIFIER, { server_physical_scale.x, server_physical_scale.y, server_physical_scale.z, client_visual_scale.x, client_visual_scale.y, client_visual_scale.z, disable_client_physics })
		end

		return true
	end

	InternalScale = Scale

	function ResetScale(ent, preserve_constraint_locations)
		local size_handler = FindSizeHandler(ent)
		local was_resized = IsValidEntity(size_handler)

		InternalFixPhysicalSize(ent, preserve_constraint_locations)

		InternalFixVisualSize(ent)

		if (was_resized) then size_handler:Remove() end

		if IsDuplicatorRegistered then
			duplicator.ClearEntityModifier(ent, ENTITY_MODIFIER)
		end

		ent.EntityResizerOriginalOBB = nil

		return true
	end

	InternalResetScale = ResetScale
	--#endregion

	--#region saverestore/duplicator registration
	function RegisterSaveRestore()
		saverestore.AddSaveHook(COMMAND_PREFIX, function(save)
			save:StartBlock(COMMAND_PREFIX .. "_SaveData")

			local EntitiesToSave = {}

			for ent, sizedata in pairs(ResizedEntities) do
				if (IsValidEntity(ent)) then
					table.insert(EntitiesToSave, { ent, sizedata })
				else
					ResizedEntities[ent] = nil
				end
			end

			local l = #EntitiesToSave

			save:WriteInt(l)

			for Key = 1, l do
				local Factory = EntitiesToSave[Key]

				local ent = Factory[1]

				save:WriteEntity(ent)

				local savedata = { Factory[2] }

				if (HasValidPhysics(ent)) then
					local physobj = ent:GetPhysicsObject()

					if (IsValidPhysicsObject(physobj)) then
						savedata[2] = {
							physobj:IsGravityEnabled(),
							physobj:GetMaterial(),
							physobj:IsCollisionEnabled(),
							physobj:IsDragEnabled(),
							physobj:GetVelocity(),
							physobj:GetAngleVelocity(),
							physobj:IsMotionEnabled(),

							physobj:IsAsleep()
						}
					end
				end

				saverestore.WriteTable(savedata, save)
			end

			save:EndBlock()
		end)

		local EntitiesToRestore = {}

		saverestore.AddRestoreHook(COMMAND_PREFIX, function(restore)
			local name = restore:StartBlock()
			if (name == COMMAND_PREFIX .. "_SaveData") then
				local l = restore:ReadInt()

				for i = 1, l do
					local ent = restore:ReadEntity()

					local savedata = saverestore.ReadTable(restore)

					if (IsValidEntity(ent)) then
						EntitiesToRestore[ent] = savedata
					end
				end
			end
			restore:EndBlock()
		end)

		hook.Add("Restored", COMMAND_PREFIX, function()
			local PhysicsData_Restore = {}

			for ent, savedata in pairs(EntitiesToRestore) do
				local sizedata = savedata[1]

				ResizedEntities[ent] = sizedata

				local physdata = savedata[2]

				if (physdata) then
					local scale = sizedata[1]

					StoreConstraintData(ent)
					PhysicsData_Restore[ent] = physdata

					local success = ResizePhysics(ent, scale)

					ent:SetCollisionBounds(sizedata[2] * scale, sizedata[3] * scale)

					if (success) then
						local physobj = ent:GetPhysicsObject()

						physobj:SetMass(math.Clamp(sizedata[4] * scale.x * scale.y * scale.z, 0.1, 50000))
						physobj:SetDamping(0, 0)
					else
						PhysicsData_Restore[ent] = nil
					end
				end

				EntitiesToRestore[ent] = nil
			end

			ApplyConstraintData()

			for ent, physdata in pairs(PhysicsData_Restore) do
				local physobj = ent:GetPhysicsObject()

				physobj:EnableGravity(physdata[1])
				physobj:SetMaterial(physdata[2])
				physobj:EnableCollisions(physdata[3])
				physobj:EnableDrag(physdata[4])
				physobj:SetVelocity(physdata[5])
				physobj:AddAngleVelocity(physdata[6] - physobj:GetAngleVelocity())
				physobj:EnableMotion(physdata[7])

				if (physdata[8]) then physobj:Sleep() else physobj:Wake() end

				if (ent.IsMotionControlled) then o_StartMotionController(ent) end
			end
		end)
	end

	InternalRegisterSaveRestore = RegisterSaveRestore

	function RegisterDuplicator()
		duplicator.RegisterEntityModifier(ENTITY_MODIFIER, function(ply, ent, data)
			local server_physical_scale = Vector(data[1], data[2], data[3])
			local client_visual_scale = Vector(data[4], data[5], data[6])

			if (server_physical_scale ~= RESET) and (HasValidPhysics(ent)) then
				local physobj = ent:GetPhysicsObject()

				if (IsValidPhysicsObject(physobj)) then
					local sizedata = CreateSizeData(ent, physobj)
					sizedata[1]:Set(server_physical_scale)

					StorePhysicsData(physobj)

					local success = ResizePhysics(ent, server_physical_scale)

					if (data[7]) then
						GetSizeHandler(ent):SetActualPhysicsScale(tostring(RESET))
					else
						GetSizeHandler(ent):SetActualPhysicsScale(tostring(server_physical_scale))
					end

					ent:SetCollisionBounds(sizedata[2] * server_physical_scale, sizedata[3] * server_physical_scale)

					if (success) then
						physobj = ent:GetPhysicsObject()

						physobj:SetMass(math.Clamp(sizedata[4] * server_physical_scale.x * server_physical_scale.y * server_physical_scale.z, 0.1, 50000))
						physobj:SetDamping(0, 0)

						ApplyPhysicsData(physobj)

						physobj:Wake()

						if (ent.IsMotionControlled) then o_StartMotionController(ent) end
					end
				end
			end

			local handler = GetSizeHandler(ent)
			handler:SetVisualScale(tostring(client_visual_scale))
		end)
	end
	InternalRegisterDuplicator = RegisterDuplicator
	--#endregion
end

function Scale(ent, scale)
	if SERVER then
		InternalScale(ent, scale, scale, true, false, true, false, nil, math.huge)
	end
end

function ScaleEx(ent, server_physical_scale, client_visual_scale, scale_visual_with_physical, disable_client_physics, clamp, preserve_constraint_locations, msg_callback, vertex_limit)
	if SERVER then
		InternalScale(ent, server_physical_scale, client_visual_scale, scale_visual_with_physical, disable_client_physics, clamp, preserve_constraint_locations, msg_callback, vertex_limit)
	end
end

function ResetScale(ent, preserve_constraint_locations)
	if SERVER then
		InternalResetScale(ent, preserve_constraint_locations)
	end
end

if (CLIENT) then
	--#region Util functions
	local function IsValidModel(mdl)
		return isstring(mdl) and util.IsValidModel(mdl)
	end

	local ResizedEntities = {}

	local function CreateSizeData(ent)
		for k, v in pairs(ResizedEntities) do if (not IsValidEntity(k)) then ResizedEntities[k] = nil end end

		local sizedata = {}

		sizedata[1] = Vector(1, 1, 1)
		sizedata[2], sizedata[3] = ent:GetRenderBounds()

		ResizedEntities[ent] = sizedata

		return sizedata
	end

	local function IsBig(scale)
		if (scale.x >= 4) then
			return (scale.y >= 4) or (scale.z >= 4)
		elseif (scale.y >= 4) then
			return (scale.z >= 4)
		end

		return false
	end
	--#endregion

	--#region saverestore registration (size)
	local function RegisterSaveRestore_Size()
		saverestore.AddSaveHook(COMMAND_PREFIX, function(save)
			save:StartBlock(COMMAND_PREFIX .. "_SaveData")

			local EntitiesToSave = {}

			for ent, sizedata in pairs(ResizedEntities) do
				if (IsValidEntity(ent)) then
					table.insert(EntitiesToSave, { ent, sizedata })
				else
					ResizedEntities[ent] = nil
				end
			end

			local l = #EntitiesToSave

			save:WriteInt(l)

			for Key = 1, l do
				local Factory = EntitiesToSave[Key]

				save:WriteEntity(Factory[1])

				saverestore.WriteTable(Factory[2], save)
			end

			save:EndBlock()
		end)

		saverestore.AddRestoreHook(COMMAND_PREFIX, function(restore)
			local name = restore:StartBlock()
			if (name == COMMAND_PREFIX .. "_SaveData") then
				local l = restore:ReadInt()

				for Key = 1, l do
					local ent = restore:ReadEntity()
					local sizedata = saverestore.ReadTable(restore)

					if (IsValidEntity(ent)) then
						ResizedEntities[ent] = sizedata
					end
				end
			end
			restore:EndBlock()
		end)
	end

	--#endregion

	--#region Size networking
	net.Receive(COMMAND_PREFIX .. "_set_visual_size", function(l)
		local ent = net.ReadEntity()
		local scale = net.ReadString()

		if (IsValidEntity(ent)) and (IsValidModel(ent:GetModel())) then
			scale = Vector(scale)

			local sizedata = ResizedEntities[ent] or CreateSizeData(ent)
			local m = Matrix()

			m:Scale(scale)
			ent:EnableMatrix("RenderMultiply", m)
			ent:SetRenderBounds(sizedata[2] * scale, sizedata[3] * scale)
			ent:DestroyShadow()

			if (IsBig(scale)) then ent:SetLOD(0) else ent:SetLOD(-1) end

			sizedata[1]:Set(scale)
		end
	end)

	net.Receive(COMMAND_PREFIX .. "_fix_visual_size", function(l)
		local ent = net.ReadEntity()

		if (IsValidEntity(ent)) and (IsValidModel(ent:GetModel())) then
			local sizedata = ResizedEntities[ent]

			if (not sizedata) then return end

			ent:DisableMatrix("RenderMultiply")
			ent:SetRenderBounds(sizedata[2], sizedata[3])
			ent:DestroyShadow()
			ent:SetLOD(-1)

			ResizedEntities[ent] = nil
		end
	end)
	--#endregion

	--#region Util functions
	local ClientPhysics = {}

	local function CreateClientPhysicsData(ent)
		for k, v in pairs(ClientPhysics) do if (not IsValidEntity(k)) then ClientPhysics[k] = nil end end

		local physdata = {}

		physdata[1] = Vector(1, 1, 1)

		ClientPhysics[ent] = physdata

		return physdata
	end
	--#endregion

	--#region saverestore registration (physics)
	local function RegisterSaveRestore_Physics()
		saverestore.AddSaveHook(COMMAND_PREFIX .. "_clientphysics", function(save)
			save:StartBlock(COMMAND_PREFIX .. "_PhysData")

			local EntitiesToSave = {}

			for ent, physdata in pairs(ClientPhysics) do
				if (IsValidEntity(ent)) then
					table.insert(EntitiesToSave, { ent, physdata })
				else
					ClientPhysics[ent] = nil
				end
			end

			local l = #EntitiesToSave

			save:WriteInt(l)

			for Key = 1, l do
				local Factory = EntitiesToSave[Key]

				save:WriteEntity(Factory[1])

				saverestore.WriteTable(Factory[2], save)
			end

			save:EndBlock()
		end)

		saverestore.AddRestoreHook(COMMAND_PREFIX .. "clientphysics", function(restore)
			local name = restore:StartBlock()
			if (name == COMMAND_PREFIX .. "_PhysData") then
				local l = restore:ReadInt()

				for Key = 1, l do
					local ent = restore:ReadEntity()
					local physdata = saverestore.ReadTable(restore)

					if (IsValidEntity(ent)) then
						ClientPhysics[ent] = physdata
					end
				end
			end
			restore:EndBlock()
		end)
	end
	--#endregion

	--#region saverestore registration final
	local function RegisterSaveRestore_All()
		RegisterSaveRestore_Size()
		RegisterSaveRestore_Physics()
	end

	InternalRegisterSaveRestore = RegisterSaveRestore_All
	--#endregion

	--#region Physics networking
	net.Receive(COMMAND_PREFIX .. "_set_physical_size", function(l)
		local ent = net.ReadEntity()
		local scale = net.ReadString()

		if (IsValidEntity(ent)) then
			scale = Vector(scale)

			local physdata = ClientPhysics[ent] or CreateClientPhysicsData(ent)
			local success = ResizePhysics(ent, scale)

			if (success) then
				local physobj = ent:GetPhysicsObject()

				physobj:SetPos(ent:GetPos())
				physobj:SetAngles(ent:GetAngles())
				physobj:EnableMotion(false)
				physobj:Sleep()
			end

			physdata[1]:Set(scale)
		end
	end)

	net.Receive(COMMAND_PREFIX .. "_fix_physical_size", function(l)
		local ent = net.ReadEntity()

		if (IsValidEntity(ent)) then
			local physdata = ClientPhysics[ent]

			if (not physdata) then return end

			ent:PhysicsDestroy()

			ClientPhysics[ent] = nil
		end
	end)
	--#endregion

	--#region Shadow entity functions
	function ENT:Think()
		local ent = self:GetParent()

		if (not IsValidEntity(ent)) then return end
		if (not ClientPhysics[ent]) then return end

		local physobj = ent:GetPhysicsObject()

		if (not IsValidPhysicsObject(physobj)) then return end

		physobj:SetPos(ent:GetPos())
		physobj:SetAngles(ent:GetAngles())
		physobj:EnableMotion(false)
		physobj:Sleep()
	end

	function ENT:RefreshVisualSize(ent)
		local sizedata = ResizedEntities[ent]

		if (sizedata) then
			local scale = sizedata[1]
			local m = Matrix()

			m:Scale(scale)
			ent:EnableMatrix("RenderMultiply", m)
			ent:SetRenderBounds(sizedata[2] * scale, sizedata[3] * scale)
			ent:DestroyShadow()

			if (IsBig(scale)) then ent:SetLOD(0) else ent:SetLOD(-1) end
		elseif (isfunction(self.GetVisualScale)) then
			local scale = Vector(self:GetVisualScale())

			if (scale ~= RESET) and (scale ~= EMPTY) then
				sizedata = CreateSizeData(ent)
				sizedata[1]:Set(scale)

				local m = Matrix()

				m:Scale(scale)
				ent:EnableMatrix("RenderMultiply", m)
				ent:SetRenderBounds(sizedata[2] * scale, sizedata[3] * scale)
				ent:DestroyShadow()

				if (IsBig(scale)) then ent:SetLOD(0) else ent:SetLOD(-1) end
			end
		end
	end

	function ENT:RefreshClientPhysics(ent)
		local physdata = ClientPhysics[ent]

		if (physdata) then
			local success = ResizePhysics(ent, physdata[1])

			if (success) then
				local physobj = ent:GetPhysicsObject()

				physobj:SetPos(ent:GetPos())
				physobj:SetAngles(ent:GetAngles())
				physobj:EnableMotion(false)
				physobj:Sleep()
			end
		elseif (isfunction(self.GetActualPhysicsScale)) then
			local scale = Vector(self:GetActualPhysicsScale())

			if (scale ~= RESET) and (scale ~= EMPTY) then
				physdata = CreateClientPhysicsData(ent)
				physdata[1]:Set(scale)

				local success = ResizePhysics(ent, scale)

				if (success) then
					local physobj = ent:GetPhysicsObject()

					physobj:SetPos(ent:GetPos())
					physobj:SetAngles(ent:GetAngles())
					physobj:EnableMotion(false)
					physobj:Sleep()
				end
			end
		end
	end

	function ENT:OnNetworkEntityCreated()
		local ent = self:GetParent()

		if (not IsValidEntity(ent)) then return end

		if (isfunction(self.GetVisualScale)) then
			local sizedata = ResizedEntities[ent]

			if (sizedata) then
				local scale = sizedata[1]

				local m = Matrix()

				m:Scale(scale)
				ent:EnableMatrix("RenderMultiply", m)
				ent:SetRenderBounds(sizedata[2] * scale, sizedata[3] * scale)
				ent:DestroyShadow()

				if (IsBig(scale)) then ent:SetLOD(0) else ent:SetLOD(-1) end
			else
				local scale = Vector(self:GetVisualScale())

				if (scale ~= RESET) and (scale ~= EMPTY) then
					sizedata = CreateSizeData(ent)
					sizedata[1]:Set(scale)

					local m = Matrix()

					m:Scale(scale)
					ent:EnableMatrix("RenderMultiply", m)
					ent:SetRenderBounds(sizedata[2] * scale, sizedata[3] * scale)
					ent:DestroyShadow()

					if (IsBig(scale)) then ent:SetLOD(0) else ent:SetLOD(-1) end
				end
			end
		end

		if (isfunction(self.GetActualPhysicsScale)) then
			local physdata = ClientPhysics[ent]

			if (physdata) then
				local scale = physdata[1]

				local success = ResizePhysics(ent, scale)

				if (success) then
					local physobj = ent:GetPhysicsObject()

					physobj:SetPos(ent:GetPos())
					physobj:SetAngles(ent:GetAngles())
					physobj:EnableMotion(false)
					physobj:Sleep()
				end
			else
				local scale = Vector(self:GetActualPhysicsScale())

				if (scale ~= RESET) and (scale ~= EMPTY) then
					physdata = CreateClientPhysicsData(ent)
					physdata[1]:Set(scale)

					local success = ResizePhysics(ent, scale)

					if (success) then
						local physobj = ent:GetPhysicsObject()

						physobj:SetPos(ent:GetPos())
						physobj:SetAngles(ent:GetAngles())
						physobj:EnableMotion(false)
						physobj:Sleep()
					end
				end
			end
		end
	end
	--#endregion

	--#region Entity hooks
	hook.Add("NetworkEntityCreated", COMMAND_PREFIX, function(ent)
		if (ent:GetClass() == GENERIC_PREFIX .. "sizehandler") and isfunction(ent.OnNetworkEntityCreated) then
			ent:OnNetworkEntityCreated()
		end
	end)
	--#endregion
end

--#region Shadow entity shared networking
function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "VisualScale", { KeyName = "visualscale" })

	self:NetworkVar("String", 1, "ActualPhysicsScale", { KeyName = "actualphysicsscale" })

	if (CLIENT) then
		local ent = self:GetParent()

		if (IsValidEntity(ent)) then
			if (isfunction(self.RefreshVisualSize)) then self:RefreshVisualSize(ent) end

			if (isfunction(self.RefreshClientPhysics)) then self:RefreshClientPhysics(ent) end
		end
	end
end
--#endregion

scripted_ents.Register(ENT, GENERIC_PREFIX .. "sizehandler")

--The following functions register invididual system functionality

--Register Undo functionality
function RegisterUndo()
	IsUndoRegistered = true
	InternalRegisterUndo()
end

--Register Duplicator functionality
function RegisterDuplicator()
	IsDuplicatorRegistered = true
	InternalRegisterDuplicator()
end

--Register SaveRestore functionality
function RegisterSaveRestore()
	IsSaveRestoreRegistered = true
	InternalRegisterSaveRestore()
end

--Register Cleanup functionality
function RegisterCleanup()
	IsCleanupRegistered = true
	InternalRegisterCleanup()
end

--Prevent auto registered on sandbox, this is done because a workshop release needs to Just Work TM
--The auto registration is called from the STool being loaded so if you require before that and call scales.SetShouldAutoRegisterOnSandbox(false)
--then it will not register anything automatically
local ShouldAutoRegisterOnSandbox = true

function SetShouldAutoRegisterOnSandbox(should)
	ShouldAutoRegisterOnSandbox = tobool(should)
end

function GetShouldAutoRegisterOnSandbox()
	return ShouldAutoRegisterOnSandbox
end


