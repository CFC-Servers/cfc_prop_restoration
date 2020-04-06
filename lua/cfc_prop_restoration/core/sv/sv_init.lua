local restorationFileName = "props_backup.json"
local diconnectedExpireTimes = diconnectedExpireTimes or {}
local propData = propData or {}
local expireTime = 600     -- Time (in seconds) for the player to reconnect before data is lost
local autosaveDelay = 180  -- How often (in seconds) the server saves prop data
local nextSave = CurTime() + autosaveDelay

if not file.Exists( restorationFileName, "DATA" ) then
    file.Write( restorationFileName, "" )
else
    local fileContents = file.Read( restorationFileName )
    local decodedContents = util.JSONToTable( fileContents )
    propData = decodedContents or {}
end

-- Populating diconnectedExpireTimes with crashed players
for steamid, _ in pairs( propData ) do
    diconnectedExpireTimes[steamid] = CurTime() + expireTime
end

local function savePropDataToFile()
    local encodeData = util.TableToJSON( propData )
    file.Write( restorationFileName, encodeData )
end

local function spawnInPlayerProps( ply )
    if not propData[ply:SteamID()] then return end

    ADInterface.paste( ply, propData[ply:SteamID()] )
end

local function sendRestorationNotification( ply )
    local notif = CFCNotifications.new( "CFC_PropRestorePrompt", "Buttons", true )
    notif:SetTitle( "Restore Props" )
    notif:SetText( "Restore props from previous server save?" )
    notif:AddButton( "Restore", Color(0, 255, 0), "restore" )
    notif:SetTimed( false )
    notif:SetIgnoreable( false )

    function notif:OnButtonPressed( data )
        spawnInPlayerProps( ply )
    end

    notif:Send( ply )
end

local function handleReconnect( ply )
    local plySID = ply:SteamID()

    if not propData[plySID] then return end
    diconnectedExpireTimes[plySID] = nil

    sendRestorationNotification( ply )
end

hook.Add( "PlayerInitialSpawn", "CFC_Restoration_Reconnect", handleReconnect )

local function handleDisconnect( ply )
    local plySID = ply:SteamID()

    diconnectedExpireTimes[plySID] = CurTime() + expireTime

    propData[plySID] = ADInterface.copy( ply )
    savePropDataToFile()
end

hook.Add( "PlayerDisconnected", "CFC_Restoration_Disconnect", handleDisconnect )

timer.Create( "CFC_Restoration_Think", 1, 0, function()
    -- Autosaving props
    if CurTime() >= nextSave then
        savePropDataToFile()

        nextSave = CurTime() + autosaveDelay
    end

    -- Deleting long disconnects
    for steamid, plyExpireTime in pairs( diconnectedExpireTimes ) do
        if CurTime() >= plyExpireTime then
            diconnectedExpireTimes[steamid] = nil
            propData[steamid] = nil
        end
    end
end )
