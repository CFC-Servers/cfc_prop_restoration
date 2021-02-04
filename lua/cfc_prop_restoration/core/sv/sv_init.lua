require( "cfclogger" )

local logger = CFCLogger( "Prop Restoration", "debug" )

local getOwner
hook.Add( "InitPostEntity", "PropRestoration_LocalizeCPPI", function()
    getOwner = FindMetaTable( "Entity" ).CPPIGetOwner
end )

local tableForceInsert = table.ForceInsert
local tableIsEmpty = table.IsEmpty

local entsGetAll = ents.GetAll

local getPhysicsObject = FindMetaTable( "Entity" ).GetPhysicsObject

local physSetVelocity = FindMetaTable( "PhysObj" ).SetVelocity
local physGetVelocity = FindMetaTable( "PhysObj" ).GetVelocity
local physIsValid = FindMetaTable( "PhysObj" ).IsValid

local playerSteamID64 = FindMetaTable( "Player" ).SteamID64

local playerGetHumans = player.GetHumans
local adCopy = ADInterface.copy
local adPaste = ADInterface.paste

local stringSub = string.sub
local stringNiceSize = string.NiceSize

local fileCreateDir = file.CreateDir
local fileWrite = file.Write
local fileSize = file.Size
local fileRead = file.Read
local fileExists = file.Exists
local fileFind = file.Find

local TableToJSON = util.TableToJSON
local JSONToTable = util.JSONToTable

local timerSimple = timer.Simple

local restorationDirectory = "prop_restoration"
local preSaveVelocityKey = "CFCPropRestoration_PreSaveVelocity"
local disconnectedExpireTimes = {}
local propData = {}
local queue = {}
local restorationDelays = {}
local restoreDelay = 90
local nextSave = 0
local notif

do
    local function populateDisconnectedExpireTimes()
        local expireTime = GetConVar( "cfc_proprestore_expire_delay" ):GetInt()

        local files = file.Find( restorationDirectory .. "/*.json", "DATA" )
        local fileCount = #files

        for i = 1, fileCount do
            local fileName = rawget( files, i )
            local steamID64 = stringSub( fileName, 1, -5 )

            disconnectedExpireTimes[steamID64] = CurTime() + expireTime
            logger:debug( "Adding (" .. steamID64 .. ") to the disconnectedExpireTimes table." )
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

    if not file.Exists( restorationDirectory, "DATA" ) then
        logger:debug( "Creating " .. restorationDirectory .. " directory because it does not exist.")
        fileCreateDir( restorationDirectory )
    end

    local autosaveDelay = GetConVar( "cfc_proprestore_autosave_delay" ):GetInt()
    nextSave = CurTime() + autosaveDelay

    populateDisconnectedExpireTimes()
end

local function canRestoreProps( ply )
    local restorationDelay = restorationDelays[playerSteamID64( ply )]
    if not restorationDelay then return false end

    return restorationDelays <= CurTime()
end

local function spawnInPlayerProps( ply )
    local plyPropData = propData[playerSteamID64( ply )]
    if not plyPropData then return end

    adPaste( ply, plyPropData )
end

hook.Add( "CFC_Notifications_init", "CFC_PropRestore_CreateNotif", function()
    logger:debug( "Creating notification object." )

    notif = CFCNotifications.new( "CFC_PropRestorePrompt", "Buttons", true )
    notif:SetTitle( "Restore Props" )
    notif:SetText( "Restore props from previous server save?" )
    notif:AddButton( "Restore", Color( 0, 255, 0 ), "restore" )
    notif:SetTimed( false )
    notif:SetIgnoreable( false )

    function notif:OnButtonPressed( ply, data )
        spawnInPlayerProps( ply )
    end
end )

local function addPropDataToQueue( plySteamID64, data )
    rawset( queue, plySteamID64, data )
end

local function processQueueData()
    local steamID64, data = next( queue )
    if not steamID64 or not data then return end

    logger:debug( "Handling queue for " .. steamID64 )

    local encodeData = TableToJSON( data )
    local fileName = restorationDirectory .. "/" .. steamID64 .. ".json"

    fileWrite( fileName, encodeData )

    local niceSize = stringNiceSize( fileSize( fileName, "DATA" ) )
    logger:info( "Saving prop data to " .. fileName .. " (" .. niceSize .. ")" )

    rawset( queue, steamID64, nil )
end

local function getPropsFromFile( ply )
    local plySteamID64 = playerSteamID64( ply )
    if propData[plySteamID64] then return end

    local fileName = restorationDirectory .. "/" .. plySteamID64 .. ".json"
    if not fileExists( fileName, "DATA" ) then return end

    local contents = fileRead( fileName, "DATA" )
    local decodeData = JSONToTable( contents )

    propData[plySteamID64] = decodeData
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


local function storePropVelocities( props, propCount )
    if not props then return {} end

    for i = 1, propCount do
        local prop = rawget( props, i )
        local propPhys = getPhysicsObject( prop )

        if physIsValid( propPhys ) then
            rawset( prop, preSaveVelocityKey, physGetVelocity( propPhys ) )
        end
    end
end

local function restorePropVelocities( props, propCount )
    if not props then return end

    for i = 1, propCount do
        local prop = rawget( props, i )
        local propPhys = getPhysicsObject( prop )

        if IsValid( propPhys ) then
            local vel = rawget( prop, preSaveVelocityKey )

            if vel then
                physSetVelocity( propPhys, vel )
            end
        end
    end
end

local function getAllPlayerProps()
    local playerProps = {}
    local ents = entsGetAll()
    local entCount = #ents

    for i = 1, entCount do
        local prop = rawget( ents, i )

        if IsValid( prop ) then
            local propOwner = getOwner( prop )

            if IsValid( propOwner ) then
                local ownerProps = rawget( playerProps, propOwner )
                rawset( playerProps, propOwner, tableForceInsert( ownerProps, prop ) )
            end
        end
    end

    return playerProps
end

local function handleReconnect( ply )
    local plySteamID64 = playerSteamID64( ply )

    getPropsFromFile( ply )

    if not propData[plySteamID64] then return end
    disconnectedExpireTimes[plySteamID64] = nil

    logger:info( "Sending notification to (" .. plySteamID64 .. ")" )

    timerSimple( 5, function()
        sendRestorationNotification( ply )
    end )
end

hook.Add( "PlayerInitialSpawn", "CFC_Restoration_Reconnect", handleReconnect )

local function handleDisconnect( ply )
    local plySteamID64 = playerSteamID64( ply )
    local expireTime = GetConVar( "cfc_proprestore_expire_delay" ):GetInt()
    local props = adCopy( ply )

    if not props then return end

    disconnectedExpireTimes[plySteamID64] = CurTime() + expireTime

    if not tableIsEmpty( props ) and props ~= nil then
        propData[plySteamID64] = props
    end

    logger:info( "Handling (" .. plySteamID64 .. ")'s props." )

    addPropDataToQueue( plySteamID64, props )
end

hook.Add( "PlayerDisconnected", "CFC_Restoration_Disconnect", handleDisconnect )

local function handleChatCommands( ply, text )
    if text == "!restoreprops" then
        local plySteamID64 = playerSteamID64( ply )

        if canRestoreProps( ply ) then
            local data = propData[plySteamID64]

            if data == nil or tableIsEmpty( data ) then
                ply:ChatPrint( "Couldn't find any props to restore." )
            else
                spawnInPlayerProps( ply )

                restorationDelays[plySteamID64] = CurTime() + restoreDelay
                ply:ChatPrint( "Spawninging in your props...")
            end
        else
            ply:ChatPrint( "You must wait " .. math.Round( restorationDelays[plySteamID64] - CurTime(), 0 ) .. " more seconds before using this again." )
        end

        return ""
    end
end

hook.Add( "PlayerSay", "CFC_Restoration_PlayerSay", handleChatCommands )

timer.Create( "CFC_Restoration_Think", 5, 0, function()
    local time = CurTime()

    -- Autosaving props
    if time >= nextSave and tableIsEmpty( queue ) then
        logger:info( "Autosaving player props" )

        local playersProps = getAllPlayerProps()

        local humans = playerGetHumans()
        local humanCount = #humans

        for i = 1, humanCount do
            local ply = rawget( humans, i )
            local plySteamID64 = playerSteamID64( ply )

            local plyProps = rawget( playersProps, ply )
            local plyPropsCount = #plyProps

            storePropVelocities( plyProps, plyPropsCount )

            local success, props = xpcall( adCopy, notifyOnError( ply ), ply )
            success = success and props

            if success and not tableIsEmpty( props ) and props ~= nil then
                rawset( propData, plySteamID64, props )
                addPropDataToQueue( plySteamID64, props )
            end

            restorePropVelocities( plyProps, plyPropsCount )
        end

        local autosaveDelay = GetConVar( "cfc_proprestore_autosave_delay" ):GetInt()
        nextSave = time + autosaveDelay
    end

    -- Deleting long disconnects
    for plySteamID64, plyExpireTime in pairs( disconnectedExpireTimes ) do
        if time >= plyExpireTime then
            logger:info( "Deleting entry for SteamID: " .. plySteamID64 )
            rawset( disconnectedExpireTimes, plySteamID64, nil )
            rawset( propData, plySteamID64, nil )

            file.Delete( restorationDirectory .. "/" .. plySteamID64 .. ".json" )
        end
    end

    -- Handling Queued PropData
    processQueueData()
end )
