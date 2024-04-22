require( "logger" )

local logger = Logger( "Prop Restoration" )

local restorationDirectory = "prop_restoration"
local disconnectedExpireTimes = {}
local propData = {}
local queue = {}
local restorationDelays = {}
local restorePromptDuration
local restoreDelay = 3
local nextSave = 0
local notif
local IsValid = IsValid
local noop = function() end

CreateConVar( "cfc_proprestore_expire_delay", "600", FCVAR_ARCHIVE, "Time (in seconds) for the player to reconnect before prop data is lost.", 0 )
CreateConVar( "cfc_proprestore_autosave_delay", "180", FCVAR_ARCHIVE, "How often (in seconds) the server saves prop data", 0 )
CreateConVar( "cfc_proprestore_notification_timeout", "240", FCVAR_ARCHIVE, "How long (in seconds) the restore prompt notification will display for players when they join", 0 )

do
    local function populateDisconnectedExpireTimes()
        local files, _ = file.Find( restorationDirectory .. "/*.json", "DATA" )
        local expireTime = GetConVar( "cfc_proprestore_expire_delay" ):GetInt()

        for _, fileName in pairs( files ) do
            local steamID64 = string.sub( fileName, 1, -5 )

            disconnectedExpireTimes[steamID64] = CurTime() + expireTime
            logger:debug( "Adding (" .. steamID64 .. ") to the disconnectedExpireTimes table." )
        end
    end

    if not file.Exists( restorationDirectory, "DATA" ) then
        logger:debug( "Creating " .. restorationDirectory .. " directory because it does not exist." )
        file.CreateDir( restorationDirectory )
    end

    local autosaveDelay = GetConVar( "cfc_proprestore_autosave_delay" ):GetInt()
    nextSave = CurTime() + autosaveDelay

    restorePromptDuration = GetConVar( "cfc_proprestore_notification_timeout" )

    populateDisconnectedExpireTimes()
end

local function canRestoreProps( ply )
    if ( restorationDelays[ply:SteamID64()] or 0 ) < CurTime() then
        return true
    end

    return false
end

local function spawnInPlayerProps( ply )
    local steamID64 = ply:SteamID64()
    if not propData[steamID64] then return end

    PropRestoration.Paste( ply, propData[steamID64] )
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

    function notif:OnButtonPressed( ply )
        spawnInPlayerProps( ply )
    end
end )

local function addPropDataToQueue( ply, data )
    queue[ply:SteamID64()] = data
end

local function processQueueData()
    local steamID64, data = next( queue )
    if not steamID64 or not data then return end

    logger:debug( "Handling queue for " .. steamID64 )

    local steamid64 = util.SteamIDTo64( steamID64 )
    local encodeData = util.TableToJSON( data )
    local fileName = restorationDirectory .. "/" .. steamid64 .. ".json"

    file.Write( fileName, encodeData )

    local fileSize = string.NiceSize( file.Size( fileName, "DATA" ) )
    logger:debug( "Saving prop data to " .. fileName .. " (" .. fileSize .. ")" )

    queue[steamID64] = nil
end

local function getPropsFromFile( ply )
    local steamID64 = ply:SteamID64()
    if propData[steamID64] then return end

    local fileName = restorationDirectory .. "/" .. ply:SteamID64() .. ".json"
    if not file.Exists( fileName, "DATA" ) then return end

    local contents = file.Read( fileName, "DATA" )
    local decodeData = util.JSONToTable( contents )

    propData[steamID64] = decodeData
end

local function sendRestorationNotification( ply )
    if not notif then return end
    notif:Send( ply )
end

local function getEntityRestorers( ents )
    if not ents then return {} end
    local restorers = {}
    local entCount = #ents

    for i = 1, entCount do
        local ent = ents[i]

        if IsValid( ent ) then
            local physObj = ent:GetPhysicsObject()
            if IsValid( physObj ) and not physObj:IsAsleep() then
                local velocity, angVelocity
                if physObj then
                    velocity = physObj:GetVelocity()
                    angVelocity = physObj:GetAngleVelocity()
                end

                restorers[i] = function()
                    physObj:SetVelocity( velocity )
                    physObj:SetAngleVelocity( angVelocity )
                end
            end
        else
            restorers[i] = noop
        end
    end

    return restorers
end

local function runRestorers( restorers )
    if not restorers then return end
    local restorerCount = #restorers

    for i = 1, restorerCount do
        ProtectedCall( restorers[i] )
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
    local steamID64 = ply:SteamID64()

    getPropsFromFile( ply )

    if not propData[steamID64] then return end
    disconnectedExpireTimes[steamID64] = nil

    logger:info( "Sending notification to (" .. steamID64 .. ")" )

    timer.Simple( 5, function()
        sendRestorationNotification( ply )
    end )
end

hook.Add( "PlayerInitialSpawn", "CFC_Restoration_Reconnect", handleReconnect )

local function saveProps( time )
    if not table.IsEmpty( queue ) then return end

    time = time or CurTime()

    logger:debug( "Autosaving player props" )

    local playersProps = getAllPlayerProps()

    for _, ply in pairs( player.GetHumans() ) do
        hook.Run( "CFC_PropRestore_SavingPlayer", ply )

        local propVelocities = getEntityRestorers( playersProps[ply] )
        local copyObj = PropRestoration.Copy( ply )

        if copyObj then
            propData[ply:SteamID64()] = copyObj
            addPropDataToQueue( ply, copyObj )
        end

        runRestorers( propVelocities )
        hook.Run( "CFC_PropRestore_SavingPlayerFinished", ply )
    end

    local autosaveDelay = GetConVar( "cfc_proprestore_autosave_delay" ):GetInt()
    nextSave = time + autosaveDelay
end

hook.Add( "CFC_DailyRestart_SoftRestart", "CFC_PropRestore_SaveProps", saveProps )

local function handleDisconnect( ply )
    local steamID64 = ply:SteamID64()
    local expireTime = GetConVar( "cfc_proprestore_expire_delay" ):GetInt()
    local copyObj = PropRestoration.Copy( ply )
    if not copyObj then return end

    disconnectedExpireTimes[steamID64] = CurTime() + expireTime

    propData[steamID64] = props

    logger:debug( "Handling (" .. steamID64 .. ")'s props." )

    addPropDataToQueue( ply, props )
end

hook.Add( "PlayerDisconnected", "CFC_Restoration_Disconnect", handleDisconnect )

local function handleChatCommands( ply, text )
    local exp = string.Explode( " ", text )
    local command = exp[1]

    if command == "!restoreprops" or command == "!proprestore" then
        local steamID64 = ply:SteamID64()

        if canRestoreProps( ply ) then
            if notif then
                notif:RemovePopups( ply )
            end

            local data = propData[steamID64]
            if data == nil or table.IsEmpty( data ) then
                ply:ChatPrint( "Couldn't find any props to restore." )
            else
                spawnInPlayerProps( ply )

                restorationDelays[steamID64] = CurTime() + restoreDelay
                ply:ChatPrint( "Spawning in your props..." )
            end
        else
            ply:ChatPrint( "You must wait " .. math.Round( restorationDelays[steamID64] - CurTime(), 0 ) .. " more seconds before using this again." )
        end

        return ""
    end

    if command == "!proprestoresave" then
        if ply:IsAdmin() then
            saveProps()
            ply:ChatPrint( "Saved everyones props." )
        end

        return ""
    end
end

hook.Add( "PlayerSay", "CFC_Restoration_PlayerSay", handleChatCommands )

timer.Create( "CFC_Restoration_Think", 5, 0, function()
    local time = CurTime()

    -- Autosaving props
    if time >= nextSave then
        saveProps( time )
    end

    -- Deleting long disconnects
    for steamID64, plyExpireTime in pairs( disconnectedExpireTimes ) do
        if time >= plyExpireTime then
            logger:debug( "Deleting entry for SteamID: " .. steamID64 )

            disconnectedExpireTimes[steamID64] = nil
            propData[steamID64] = nil

            file.Delete( restorationDirectory .. "/" .. steamID64 .. ".json" )
        end
    end

    -- Handling Queued PropData
    processQueueData()
end )
