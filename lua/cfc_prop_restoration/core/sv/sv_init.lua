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

local function spawnInPlayerProps( ply )
    local _ents = prop[ply:SteamID64()]
    duplicator.Paste( ply, _ents[1], _ents[2] )
end

local function handleReconnect( ply )
    -- NET MESSAGE CLIENT HERE --
    spawnInPlayerProps( ply )
end

hook.Add( "PlayerInitialSpawn", "CFC_Restoration_Reconnect", handleReconnect )

local function handleDisconnect( ply )
    local player_props = {}
    local player_sid = ply:SteamID64()

    for _, prop in pairs( ents.GetAll() ) do
        if prop:CPPIGetOwner() ~= ply then continue end
        if not duplicator.IsAllowed( prop:GetClass() ) then return end

        table.insert( player_props, prop )
    end

    prop_data[player_sid] = duplicator.CopyEnts( player_props )
    recent_disconnects[player_sid] = CurTime() + expire_time
end

hook.Add( "PlayerDisconnected", "CFC_Restoration_Disconnect", handleDisconnect )

local function restorationThink()
    -- Autosaving props
    if CurTime() >= next_save then
        savePropDataToFile()

        next_save = CurTime() + autosave_delay
    end

    -- Deleting long disconnects
    for sid64, expire_time in pairs(recent_disconnects) do
        if CurTime() >= expire_time then
            recent_disconnects[sid64] = nil
        end
    end
end

hook.Add( "Tick", "CFC_Restoration_Tick", restorationThink )
