local restorationFileName = "props_backup.json"
local recent_disconnects = recent_disconnects or {}
local propData = propData or {}
local expireTime = 600     -- Time (in seconds) for the player to reconnect before data is lost
local autosaveDelay = 180  -- How often (in seconds) the server saves prop data
local nextSave = CurTime() + autosaveDelay

util.AddNetworkString( "Restore_AlertReconnectingPlayer" )
util.AddNetworkString( "Restore_RestorePlayerProps" )

if not file.Exists( restorationFileName, "DATA" ) then
    file.Write( restorationFileName, "" )
else
    local fileContents = file.Read( restorationFileName )
    local decodedContents = util.JSONToTable( fileContents )
    propData = decodedContents or {}
end

-- Populating recent_disconnects with crashed players
for steamid, _ in pairs( propData ) do
    recent_disconnects[steamid] = CurTime() + expireTime
end

local function savePropDataToFile()
    local encodeData = util.TableToJSON( propData )
    file.Write( restorationFileName, encodeData )
end

local function spawnInPlayerProps( ply )
    if not propData[ply:SteamID()] then return end

    ADInterface.paste( ply, propData[ply:SteamID()] )
end

local function handleReconnect( ply )
    local plySID = ply:SteamID()

    if not propData[plySID] then return end
    recent_disconnects[plySID] = nil

    net.Start( "Restore_AlertReconnectingPlayer" )
    net.Send( ply )
end

hook.Add( "PlayerInitialSpawn", "CFC_Restoration_Reconnect", handleReconnect )

-- Handling user confirmation
net.Receive( "Restore_RestorePlayerProps", function( len, ply )
    spawnInPlayerProps( ply )
end )

local function handleDisconnect( ply )
    local plySID = ply:SteamID()

    recent_disconnects[plySID] = CurTime() + expireTime

    propData[plySID] = ADInterface.copy( ply )
    savePropDataToFile()
end

hook.Add( "PlayerDisconnected", "CFC_Restoration_Disconnect", handleDisconnect )

timer.Create( "restorationThink", 1, 0, function()
    -- Autosaving props
    if CurTime() >= nextSave then
        savePropDataToFile()

        nextSave = CurTime() + autosaveDelay
    end

    -- Deleting long disconnects
    for steamid, plyExpireTime in pairs( recent_disconnects ) do
        if CurTime() >= plyExpireTime then
            recent_disconnects[steamid] = nil
            propData[steamid] = nil
        end
    end
end )
