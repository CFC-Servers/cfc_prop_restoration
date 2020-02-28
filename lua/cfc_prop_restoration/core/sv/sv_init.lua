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
for sid64, _ in pairs(propData) do
    recent_disconnects[sid64] = CurTime() + expireTime
end

local function savePropDataToFile()
    local encodeData = util.TableToJSON( propData )
    file.Write( restorationFileName, encodeData )
end

local function isValidPlayer( ent )
    return IsValid( ent ) and ent:IsPlayer()
end

local function spawnInPlayerProps( ply )
    local _ents = propData[ply:SteamID()]
    local playerProps = duplicator.Paste( ply, _ents.Entities, _ents.Constraints )

    for _, ent in pairs( playerProps ) do
        ent:CPPISetOwner( ply )

        -- Not perfect but its nice to have
        undo.Create( "[Recovered] Entity (" .. ent:GetClass() .. ")" )
            undo.AddEntity( ent )
            undo.SetPlayer( ply )
        undo.Finish()
    end
end

local function handleReconnect( ply )
    local plySteamID = ply:SteamID()

    if propData[plySteamID] == nil then return end
    recent_disconnects[plySteamID] = nil

    net.Start( "Restore_AlertReconnectingPlayer" )
    net.Send( ply )
end

hook.Add( "PlayerInitialSpawn", "CFC_Restoration_Reconnect", handleReconnect )

net.Receive( "Restore_RestorePlayerProps", function( len, ply )
    spawnInPlayerProps( ply )
end )

local function handleDisconnect( ply )
    local playerProps = {}
    local plySteamID = ply:SteamID()

    for _, prop in pairs( ents.GetAll() ) do
        local plyIsCPPIOwner = prop:CPPIGetOwner() == ply
        local classIsAllowed = duplicator.IsAllowed( prop:GetClass() )

        if plyIsCPPIOwner and classIsAllowed then
            table.insert( playerProps, prop )
        end
    end

    recent_disconnects[plySteamID] = CurTime() + expireTime

    -- If the player didnt spawn props resort to prop data from server
    -- prevents losing props after a double crash
    if table.IsEmpty( playerProps ) then return end

    propData[plySteamID] = duplicator.CopyEnts( playerProps )
end

hook.Add( "PlayerDisconnected", "CFC_Restoration_Disconnect", handleDisconnect )

timer.Create( "restorationThink", 5, 0, function()
    -- Autosaving props
    if CurTime() >= nextSave then
        savePropDataToFile()

        nextSave = CurTime() + autosaveDelay
    end

    -- Deleting long disconnects
    for sid64, expireTime in pairs( recent_disconnects ) do
        if CurTime() >= expireTime then
            recent_disconnects[sid64] = nil
            propData[sid64] = nil
        end
    end
end )
