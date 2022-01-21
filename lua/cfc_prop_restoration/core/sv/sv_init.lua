-- Handles the main interaction/operation

require( "logger" )

local logger = Logger( "Phoenix", "debug" )
local noop = function() end

Phoenix = {
    logger = logger,

    -- Mock this out, when notifs exist they'll update it
    notif = {
        Send = noop,
        RemovePopups = noop
    }
}

local restorationDirectory = "phoenix"
local disconnectedExpireTimes = {}
local playerData = {}
local restorationDelays = {}
local restorePromptDuration
local restoreDelay = 90
local nextSave = 0

do
    local function populateDisconnectedExpireTimes()
        local files, _ = file.Find( restorationDirectory .. "/*.json", "DATA" )
        local expireTime = GetConVar( "cfc_phoenix_expire_delay" ):GetInt()

        for _, fileName in pairs( files ) do
            local fname = string.sub( fileName, 1, -5 )
            local steamid = util.SteamIDFrom64( fname )

            disconnectedExpireTimes[steamid] = CurTime() + expireTime
            logger:debug( "Adding (" .. steamid .. ") to the disconnectedExpireTimes table." )
        end
    end

    if not file.Exists( restorationDirectory, "DATA" ) then
        logger:debug( "Creating " .. restorationDirectory .. " directory because it does not exist.")
        file.CreateDir( restorationDirectory )
    end

    local autosaveDelay = GetConVar( "cfc_phoenix_autosave_delay" ):GetInt()
    nextSave = CurTime() + autosaveDelay

    restorePromptDuration = GetConVar( "cfc_phoenix_notification_timeout" )

    populateDisconnectedExpireTimes()
end

local function canRestorePlayerData( ply )
    if ( restorationDelays[ply:SteamID()] or 0 ) < CurTime() then
        return true
    end

    return false
end

function Phoenix.applyPlayerData( ply )
    local data = playerData[ply:SteamID()]
    if not data then return end

    local propData = data.props
    if propData then
        ADInterface.paste( ply, propData )
    end

    local other = data.other
    if other then
        hook.Run( "CFC_Phoenix_ApplyPlayerData", data.other )
    end
end

local function addPropDataToQueue( ply, data )
    saveQueue[ply:SteamID()] = data
end

local function getDataForPly( ply )
    return Storage.readDataForPly( ply )
end

local function sendRestorationNotification( ply )
    if not notif then return end
    notif:Send( ply )
end

local function notifyOnError( ply )
    return function( err )
        local message = "ERROR: " .. err

        logger:error( err )
    end
end


local function handleReconnect( ply )
    local plySteamID = ply:SteamID()

    readDataForPly( ply )

    if not playerData[plySteamID] then return end
    disconnectedExpireTimes[plySteamID] = nil

    logger:info( "Sending notification to (" .. plySteamID .. ")" )

    timer.Simple( 5, function()
        sendRestorationNotification( ply )
    end )
end

hook.Add( "PlayerInitialSpawn", "CFC_Phoenix_Reconnect", handleReconnect )

local function handleDisconnect( ply )
    local plySteamID = ply:SteamID()
    local expireTime = GetConVar( "cfc_phoenix_expire_delay" ):GetInt()

    local props = ADInterface.copy( ply )
    if not props then return end

    disconnectedExpireTimes[plySteamID] = CurTime() + expireTime

    if props and not table.IsEmpty( props ) then
        playerData[plySteamID] = props
    end

    logger:info( "Handling (" .. ply:SteamID() .. ")'s props." )

    addPropDataToQueue( ply, props )
end

hook.Add( "PlayerDisconnected", "CFC_Phoenix_Disconnect", handleDisconnect )

local function handleChatCommands( ply, text )
    text = string.Replace( text, " ", "" )
    if not string.StartWith( text, "!restoreprops" ) then return end

    Phoenix.notif:RemovePopups( ply )

    local data = playerData[ply:SteamID()]

    if data == nil or table.IsEmpty( data ) then
        ply:ChatPrint( "Couldn't find anything to restore." )
    else
        Phoenix.applyPlayerData( ply )

        restorationDelays[ply:SteamID()] = CurTime() + restoreDelay
        ply:ChatPrint( "Spawning in your props...")
    end

    return ""
end

hook.Add( "PlayerSay", "CFC_Phoenix_PlayerSay", handleChatCommands )

local function buildPlayerData( ply, playersProps )
    local plyData = {
        propData = {}
    }

    local propVelocities = getEntityRestorers( playersProps )

    local success, props = xpcall( ADInterface.copy, notifyOnError( ply ), ply )
    success = success and props

    if success and props and not table.IsEmpty( props ) then
        plyData.propData = props
        addPropDataToQueue( ply, props )
    end

    runRestorers( propVelocities )
end

local function saveData( time )
    if not table.IsEmpty( saveQueue ) then return end

    time = time or CurTime()

    logger:info( "Autosaving player data" )

    local playersProps = getAllPlayerProps()

    for _, ply in pairs( player.GetHumans() ) do
        local data = buildPlayerData( ply, playersProps[ply] )
        playerData[ply:SteamID()] = data
    end

    local autosaveDelay = GetConVar( "cfc_proprestore_autosave_delay" ):GetInt()
    nextSave = time + autosaveDelay
end

-- TODO: Move this elsewhere
hook.Add( "CFC_DailyRestart_SoftRestart", "CFC_Phoenix_SaveProps", saveData )

timer.Create( "CFC_Phoenix_Think", 5, 0, function()
    local time = CurTime()

    -- Autosaving props
    if time >= nextSave then
        saveData( time )
    end

    -- Deleting long disconnects
    for steamid, plyExpireTime in pairs( disconnectedExpireTimes ) do
        if time >= plyExpireTime then
            logger:info( "Deleting entry for SteamID: " .. steamid )
            local steamid64 = util.SteamIDTo64( steamid )

            disconnectedExpireTimes[steamid] = nil
            playerData[steamid] = nil

            file.Delete( restorationDirectory .. "/" .. steamid64 .. ".json" )
        end
    end

    -- Handling Queued PropData
    processQueueData()
end )
