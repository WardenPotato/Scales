![scales_banner](https://github.com/WardenPotato/Scales/assets/35919125/3e38592d-a073-44ac-9274-e37d0219e026)


# Scales!
An advanced GMod entity resizing library and STool.

Dont you just love how scaling models on entities causes pain, misery and sadness in multiplayer environments?
Well so do I, so I decided to make this library based off of the popular Prop Resizer addon.

This does not suffer from all the usual issues and has working clientside physics!

The library focuses on developers and server owners mainly that want to use this functionality from their own code and custom content.

## Installing
Installation is straightforward and simple, you can directly clone this repo into your addons folder or only use the module file if you dont care about the STool.
Keep in mind to use a lowercase folder name if youre using this on linux.

The module can be loaded using `require("scales")`.

## Autoregistration on sandbox
On sandbox the functionality for: Cleanup, SaveRestore, Duplicator and Undo. Is automatically registered, this can be disabled by calling `scales.SetShouldAutoRegisterOnSandbox(false)` before the STool loads.
This autoloading functionality is not present on gamemodes that arent sandbox derived.

## Convars on sandbox
On sandbox the following convars are registered to prevent abuse of the STool, this doesnt not effect the API functions.

`scales_clamp`: Force the Entity Resizer to clamp its values. (Default: on)

`scales_convexvertexlimit`: Impose vertex limit to prevent lag. (Default: 500)

`scales_propsonly`: Only allow the tool to be used on prop_physics. (Default: on)

## API Functions
These API functions are available under `scales.` after the module has loaded.

```lua
--Scale an entity. by default this: has no vertex_limit, does clamping, doesnt preserve constraint locations.
--Arguments: Entity, Vector
--Realm: Server
Scale(ent, scale)

--Scale an entity, but with many more options, 
--Arguments: Entity, Vector, Vector, Boolean, Boolean, Boolean, Boolean, Function(msg), Number
--Realm: Server
ScaleEx(ent, server_physical_scale, client_visual_scale, scale_visual_with_physical, disable_client_physics, clamp, preserve_constraint_locations, msg_callback, vertex_limit)

--Reset the scaling of an entity, preserve_constraint_locations is false by default.
--Arguments: Entity, Boolean
--Realm: Server
ResetScale(ent, preserve_constraint_locations)



--Register Undo library integration
--Realm: Server
RegisterUndo()

--Register Duplicator library integration
--Realm: Server
RegisterDuplicator()

--Register SaveRestore library integration
--Realm: Shared
RegisterSaveRestore()

--Register Cleanup library integration
--Realm: Server
RegisterCleanup()


--Set if the above integrations should be automatically registered in sandbox
--Realm: Shared
SetShouldAutoRegisterOnSandbox(should)

--Get if the above integrations should be automatically registered in sandbox
--Realm: Shared
GetShouldAutoRegisterOnSandbox()
```

## TODO:
- [ ] Lua language server notation comments
