require( "cfclogger" )

CFC_PropRestore = CFC_PropRestore or {}

local logger = CFCLogger( "Prop Restoration", "debug" )

local restorationDirectory = "prop_restoration"
local disconnectedExpireTimes = {}
local propData = {}
local queue = {}
local restorationDelays = {}
local restorePromptDuration
local restoreDelay = 90
local nextSave = 0
local notif

do
    local function populateDisconnectedExpireTimes()
        local files, _ = file.Find( restorationDirectory .. "/*.json", "DATA" )
        local expireTime = GetConVar( "cfc_proprestore_expire_delay" ):GetInt()

        for _, fileName in pairs( files ) do
            local fname = string.sub( fileName, 1, -5 )
            local steamid = util.SteamIDFrom64( fname )

            disconnectedExpireTimes[steamid] = CurTime() + expireTime
            logger:debug( "Adding (" .. steamid .. ") to the disconnectedExpireTimes table." )
        end
    end

    if not ConVarExists( "cfc_proprestore_expire_delay" ) then
        logger:debug( "Creating ConVar \"cfc_proprestore_expire_delay\" because it does not exist." )

        CreateConVar(
            "cfc_proprestore_expire_delay",
            600,
            FCVAR_ARCHIVE,
            "Time (in seconds) for the player to reconnect before prop data is lost.",
            0
        )
    end

    if not ConVarExists( "cfc_proprestore_autosave_delay" ) then
        logger:debug( "Creating ConVar \"cfc_proprestore_autosave_delay\" because it does not exist." )

        CreateConVar(
            "cfc_proprestore_autosave_delay",
            180,
            FCVAR_ARCHIVE,
            "How often (in seconds) the server saves prop data",
            0
        )
    end

    if not ConVarExists( "cfc_proprestore_notification_timeout" ) then
        logger:debug( "Creating ConVar \"cfc_proprestore_notification_timeout\" because it does not exist." )

        CreateConVar(
            "cfc_proprestore_notification_timeout",
            240,
            FCVAR_ARCHIVE,
            "How long (in seconds) the restore prompt notification will display for players when they join",
            0
        )
    end

    if not file.Exists( restorationDirectory, "DATA" ) then
        logger:debug( "Creating " .. restorationDirectory .. " directory because it does not exist.")
        file.CreateDir( restorationDirectory )
    end

    local autosaveDelay = GetConVar( "cfc_proprestore_autosave_delay" ):GetInt()
    nextSave = CurTime() + autosaveDelay

    restorePromptDuration = GetConVar( "cfc_proprestore_notification_timeout" )

    populateDisconnectedExpireTimes()
end

local function canRestoreProps( ply )
    if ( restorationDelays[ply:SteamID()] or 0 ) < CurTime() then
        return true
    end

    return false
end

local function spawnInPlayerProps( ply )
    if not propData[ply:SteamID()] then return end

    ADInterface.paste( ply, propData[ply:SteamID()] )
end

hook.Add( "CFC_Notifications_init", "CFC_PropRestore_CreateNotif", function()
    logger:debug( "Creating notification object." )

    notif = CFCNotifications.new( "CFC_PropRestorePrompt", "Buttons", true )
    notif:SetTitle( "Restore Props" )
    notif:SetText( "Restore props from previous server save?\n(Press the button or use the !restoreprops command)" )
    notif:AddButton( "Restore", Color( 0, 255, 0 ), "restore" )
    notif:SetDisplayTime( restorePromptDuration:GetFloat() )
    notif:SetTimed( true )
    notif:SetIgnoreable( false )

    function notif:OnButtonPressed( ply, data )
        spawnInPlayerProps( ply )
    end
end )

local function addPropDataToQueue( ply, data )
    queue[ply:SteamID()] = data
end

local function processQueueData()
    local steamid, data = next( queue )
    if not steamid or not data then return end

    logger:debug( "Handling queue for " .. steamid )

    local steamid64 = util.SteamIDTo64( steamid )
    local encodeData = util.TableToJSON( data )
    local fileName = restorationDirectory .. "/" .. steamid64 .. ".json"

    file.Write( fileName, encodeData )

    local fileSize = string.NiceSize( file.Size( fileName, "DATA" ) )
    logger:info( "Saving prop data to " .. fileName .. " (" .. fileSize .. ")" )

    queue[steamid] = nil
end

local function getPropsFromFile( ply )
    if propData[ply:SteamID()] then return end

    local fileName = restorationDirectory .. "/" .. ply:SteamID64() .. ".json"
    if not file.Exists( fileName, "DATA" ) then return end

    local contents = file.Read( fileName, "DATA" )
    local decodeData = util.JSONToTable( contents )

    propData[ply:SteamID()] = decodeData
end

local function sendRestorationNotification( ply )
    if not notif then return end
    notif:Send( ply )
end

local function notifyOnError( ply )
    return function( err )
        local message = "ERROR: " .. err

        logger:error( err )
        CFCNotifications.sendSimple( "CFC_PropRestoreError", "Prop Restoration error", message, ply )
    end
end

local function getPropVelocities( props )
    local velocities = {}

    if not props then return {} end

    for _, prop in pairs( props ) do
        local propPhys = prop:GetPhysicsObject()
        if IsValid( propPhys ) then
            velocities[prop] = propPhys:GetVelocity()
        end
    end

    return velocities
end


local function restorePropVelocities( props )
    if not props then return end
    for prop, vel in pairs( props ) do
        local propPhys = prop:GetPhysicsObject()

        if IsValid( propPhys ) then
            propPhys:SetVelocity( vel )
        end
    end
end

local function getAllPlayerProps()
    local playerProps = {}
    for _, prop in pairs( ents.GetAll() ) do
        if IsValid( prop ) then
            local propOwner = prop:CPPIGetOwner()

            if IsValid( propOwner ) then
                playerProps[propOwner] = playerProps[propOwner] or {}
                table.insert( playerProps[propOwner], prop )
            end
        end
    end
    return playerProps
end

local function handleReconnect( ply )
    local plySID = ply:SteamID()

    getPropsFromFile( ply )

    if not propData[plySID] then return end
    disconnectedExpireTimes[plySID] = nil

    logger:info( "Sending notification to (" .. ply:SteamID() .. ")" )

    timer.Simple( 5, function()
        sendRestorationNotification( ply )
    end )
end

hook.Add( "PlayerInitialSpawn", "CFC_Restoration_Reconnect", handleReconnect )

local function handleDisconnect( ply )
    local plySID = ply:SteamID()
    local expireTime = GetConVar( "cfc_proprestore_expire_delay" ):GetInt()
    local props = ADInterface.copy( ply )
    if not props then return end

    disconnectedExpireTimes[plySID] = CurTime() + expireTime

    if not table.IsEmpty( props ) and props ~= nil then
        propData[plySID] = props
    end

    logger:info( "Handling (" .. ply:SteamID() .. ")'s props." )

    addPropDataToQueue( ply, props )
end

hook.Add( "PlayerDisconnected", "CFC_Restoration_Disconnect", handleDisconnect )

local function handleChatCommands( ply, text )
    local exp = string.Explode( " ", text )

    if exp[1] == "!restoreprops" then
        if canRestoreProps( ply ) then
            if notif then
                notif:RemovePopups( ply )
            end

            local data = propData[ply:SteamID()]
            if data == nil or table.IsEmpty( data ) then
                ply:ChatPrint( "Couldn't find any props to restore." )
            else
                spawnInPlayerProps( ply )

                restorationDelays[ply:SteamID()] = CurTime() + restoreDelay
                ply:ChatPrint( "Spawninging in your props...")
            end
        else
            ply:ChatPrint( "You must wait " .. math.Round( restorationDelays[ply:SteamID()] - CurTime(), 0 ) .. " more seconds before using this again." )
        end

        return ""
    end
end

hook.Add( "PlayerSay", "CFC_Restoration_PlayerSay", handleChatCommands )

function CFC_PropRestore.SaveProps()
    if not table.IsEmpty( queue ) then return end

    logger:info( "Autosaving player props" )

    local playersProps = getAllPlayerProps()

    for _, ply in pairs( player.GetHumans() ) do

        local propVelocities = getPropVelocities( playersProps[ply] )

        local success, props = xpcall( ADInterface.copy, notifyOnError( ply ), ply )
        success = success and props

        if success and not table.IsEmpty( props ) and props ~= nil then
            propData[ply:SteamID()] = props
            addPropDataToQueue( ply, props )
        end

        restorePropVelocities( propVelocities )
    end

    local autosaveDelay = GetConVar( "cfc_proprestore_autosave_delay" ):GetInt()
    nextSave = time + autosaveDelay
end

timer.Create( "CFC_Restoration_Think", 5, 0, function()
    local time = CurTime()

    -- Autosaving props
    if time >= nextSave then
        CFC_PropRestore.SaveProps()
    end

    -- Deleting long disconnects
    for steamid, plyExpireTime in pairs( disconnectedExpireTimes ) do
        if time >= plyExpireTime then
            logger:info( "Deleting entry for SteamID: " .. steamid )
            local steamid64 = util.SteamIDTo64( steamid )

            disconnectedExpireTimes[steamid] = nil
            propData[steamid] = nil

            file.Delete( restorationDirectory .. "/" .. steamid64 .. ".json" )
        end
    end

    -- Handling Queued PropData
    processQueueData()
end )
