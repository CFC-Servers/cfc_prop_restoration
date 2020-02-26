local restoration_file_name = "props_backup.txt"
local recent_disconnects = recent_disconnects or {}
local prop_data = prop_data or {}
local expire_time = 300     -- Time (in seconds) for the player to reconnect before data is lost
local autosave_delay = 60   -- How often (in seconds) the server saves prop data
local next_save = CurTime() + autosave_delay

if not file.Exists( restoration_file_name, "DATA" ) then
    file.Write( restoration_file_name, "" )
else
    local fileContents = file.Read( restoration_file_name )
    local decodedContents = util.JSONToTable( fileContents )
    prop_data = decodedContents or {}
end

-- Populating recent_disconnects with crashed players
for sid64, _ in pairs(prop_data) do
    recent_disconnects[sid64] = CurTime() + expire_time
end

local function savePropDataToFile()
    local encodeData = util.TableToJSON( prop_data )
    file.Write( restoration_file_name, encodeData )
end

local function isValidPlayer( ent )
    return IsValid( ent ) and ent:IsPlayer()
end

local function spawnInPlayerProps( sid64 )

end

local function onEntCreated( ent )
    if not IsValid( ent ) then return end
    if ent:GetClass() ~= "prop_physics" then return end

    local entOwner = ent:GetOwner()
    if not isValidPlayer( entOwner ) then return end

    --[[
    What matters?
     - constraints
     - model
     - position
     - angle
     - material
     - color
    ]]

    local entity_data = {
        model = ent:GetModel(),
        pos = ent:GetPos(),
        ang = ent:GetAngles(),
        mat = ent:GetMaterial(),
        col = ent:GetColor()
        --constraints = ent:GetConstrainedEntities()
    }

    table.insert( prop_data[entOwner:SteamID64()], ent )
end

hook.Add( "OnEntityCreated", "CFC_Restoration_EntCreate", onEntCreated )

local function onEntRemove( ent )
    if not IsValid( ent ) then return end
    if ent:GetClass() ~= "prop_physics" then return end

    local entOwner = ent:GetOwner()
    if not isValidPlayer( entOwner ) then return end

    table.RemoveByValue( prop_data[entOwner:SteamID64()], ent )
end

hook.Add( "EntityRemoved", "CFC_Restoration_EntRemove", onEntRemove )

local function handleReconnect( ply )

end

hook.Add( "PlayerInitialSpawn", "CFC_Restoration_Reconnect", handleReconnect )

local function handleDisconnect( ply )
    recent_disconnects[ply:SteamID64()] = CurTime() + expire_time
end

hook.Add( "PlayerDisconnected", "CFC_Restoration_Disconnect", handleDisconnect )

local function disconnectThink()
    -- Autosaving props
    if CurTime() >= next_save then
        savePropDataToFile()
    end

    -- Deleting long disconnects
    for sid64, expire_time in pairs(recent_disconnects) do
        if CurTime() >= expire_time then
            recent_disconnects[sid64] = nil
        end
    end
end

hook.Add( "Tick", "CFC_Restoration_Tick", disconnectThink )
