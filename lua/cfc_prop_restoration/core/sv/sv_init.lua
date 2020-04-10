require( "cfclogger" )

local restorationFileName = "props_backup.json"
local diconnectedExpireTimes = diconnectedExpireTimes or {}
local propData = propData or {}
local nextSave = 0

local logger = CFCLogger( "Prop Restoration" )

do
    if not ConVarExists( "cfc_proprestore_expire_delay" ) then
        CreateConVar(
            "cfc_proprestore_expire_delay",
            600,
            FCVAR_NONE,
            "Time (in seconds) for the player to reconnect before prop data is lost.",
            0
        )
    end

    if not ConVarExists( "cfc_proprestore_autosave_delay" ) then
        CreateConVar( 
            "cfc_proprestore_autosave_delay",
            180,
            FCVAR_NONE,
            "How often (in seconds) the server saves prop data",
            0
        )
    end

    local autosaveDelay = GetConVar( "cfc_proprestore_autosave_delay" )
    nextSave = CurTime() + autosaveDelay

    if not file.Exists( restorationFileName, "DATA" ) then
        file.Write( restorationFileName, "" )
    else
        local fileContents = file.Read( restorationFileName )
        local decodedContents = util.JSONToTable( fileContents )
        propData = decodedContents or {}
    end

    -- Populating diconnectedExpireTimes with crashed players
    for steamid, _ in pairs( propData ) do
        local expireTime = GetConVar( "cfc_proprestore_expire_delay" )
        diconnectedExpireTimes[steamid] = CurTime() + expireTime
    end
end

local function savePropDataToFile()
    local encodeData = util.TableToJSON( propData )
    file.Write( restorationFileName, encodeData )

    local fileSize = string.NiceSize( file.Size( restorationFileName, "DATA" ) )
    logger:info( "Saving prop data to " .. restorationFileName .. " (" .. fileSize .. ")" )
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
    local expireTime = GetConVar( "cfc_proprestore_expire_delay" )

    diconnectedExpireTimes[plySID] = CurTime() + expireTime

    propData[plySID] = ADInterface.copy( ply )
    savePropDataToFile()
end

hook.Add( "PlayerDisconnected", "CFC_Restoration_Disconnect", handleDisconnect )

timer.Create( "CFC_Restoration_Think", 1, 0, function()
    -- Autosaving props
    if CurTime() >= nextSave then
        savePropDataToFile()

        local autosaveDelay = GetConVar( "cfc_proprestore_autosave_delay" )
        nextSave = CurTime() + autosaveDelay
    end

    -- Deleting long disconnects
    for steamid, plyExpireTime in pairs( diconnectedExpireTimes ) do
        if CurTime() >= plyExpireTime then
            logger:info( "Deleting entry for SteamID: " .. steamid )
            diconnectedExpireTimes[steamid] = nil
            propData[steamid] = nil
        end
    end
end )
