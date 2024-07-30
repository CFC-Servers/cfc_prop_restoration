require( "logger" )

local logger = Logger( "Prop Restoration" )

local restorationDirectory = "prop_restoration"
local disconnectedExpireTimes = {}
local restorationDelays = {}
local restorePromptDuration
local restoreDelay = 3
local nextSave = 0
local notif
local noop = function() end

local IsValid = IsValid

-- Table of the latest encoded dupe data for a player
-- SteamID64 -> Encoded Dupe Data
--- @type table<string, string>
local latestDupes = {}

-- Queue of prop data waiting to be encoded and saved
local saveQueue = {}

CreateConVar( "cfc_proprestore_expire_delay", "600", FCVAR_ARCHIVE, "Time (in seconds) for the player to reconnect before prop data is lost.", 0 )
CreateConVar( "cfc_proprestore_autosave_delay", "180", FCVAR_ARCHIVE, "How often (in seconds) the server saves prop data", 0 )
CreateConVar( "cfc_proprestore_notification_timeout", "240", FCVAR_ARCHIVE, "How long (in seconds) the restore prompt notification will display for players when they join", 0 )

do
    local function populateDisconnectedExpireTimes()
        local files, _ = file.Find( restorationDirectory .. "/*.txt", "DATA" )
        local expireTime = GetConVar( "cfc_proprestore_expire_delay" ):GetInt()

        for _, fileName in pairs( files ) do
            local steamID64 = string.sub( fileName, 1, -6 )

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
    local encodedDupe = latestDupes[steamID64]
    if not encodedDupe then return end

    PropRestoration.Paste( ply, encodedDupe )
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
    saveQueue[ply:SteamID64()] = data
end

local function processSaveQueue()
    local steamID64, data = next( saveQueue )
    if not steamID64 or not data then return end

    logger:debug( "Handling queue for " .. steamID64 )

    PropRestoration.Encode( data, function( encodeData )
        local fileName = restorationDirectory .. "/" .. steamID64 .. ".txt"

        file.Write( fileName, encodeData )

        local fileSize = string.NiceSize( file.Size( fileName, "DATA" ) )
        logger:debug( "Saving prop data to " .. fileName .. " (" .. fileSize .. ")" )

        latestDupes[steamID64] = encodeData
    end )

    saveQueue[steamID64] = nil
end

local function getPropsFromFile( ply )
    local steamID64 = ply:SteamID64()
    if latestDupes[steamID64] then return end

    local fileName = restorationDirectory .. "/" .. ply:SteamID64() .. ".txt"
    if not file.Exists( fileName, "DATA" ) then return end

    local contents = file.Read( fileName, "DATA" )
    latestDupes[steamID64] = contents
end

local function getEntityRestorers( entities )
    if not entities then return {} end
    local restorers = {}
    local entCount = #entities

    for i = 1, entCount do
        local ent = entities[i]

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
            else
                restorers[i] = noop
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
        local restorer = restorers[i]

        if restorer then
            ProtectedCall( restorer )
        else
            ErrorNoHalt( "Restorer at index " .. i .. " is nil." )
            PrintTable( restorers )
        end
    end
end

--- Get all props in the server and organize them by player
--- Optionally, only get the props for a specific player
--- @param only? Entity
local function getPlayerProps( only )
    local playerProps = {}
    local table_insert = table.insert

    for _, prop in ents.Iterator() do
        local propOwner = prop:CPPIGetOwner()

        -- If we're filtering, we don't want to validity check
        if (only and propOwner == only) or IsValid( propOwner ) then
            playerProps[propOwner] = playerProps[propOwner] or {}
            table_insert( playerProps[propOwner], prop )
        end
    end

    return playerProps
end

local function handleReconnect( ply )
    local steamID64 = ply:SteamID64()
    local success = ProtectedCall( getPropsFromFile, ply )

    if not success then return end
    if not latestDupes[steamID64] then return end

    disconnectedExpireTimes[steamID64] = nil

    if not notif then return end
    logger:info( "Sending notification to (" .. steamID64 .. ")" )
    notif:Send( ply )
end
hook.Add( "PlayerFullLoad", "CFC_Restoration_Reconnect", handleReconnect )

local function saveProps( time )
    if not table.IsEmpty( saveQueue ) then return end

    time = time or CurTime()

    logger:debug( "Autosaving player props" )

    local playersProps = getPlayerProps()

    for _, ply in pairs( player.GetHumans() ) do
        hook.Run( "CFC_PropRestore_SavingPlayer", ply )

        local plyProps = playersProps[ply]
        local propVelocities = getEntityRestorers( plyProps )
        local copyObj = plyProps and PropRestoration.Copy( ply, plyProps )

        if copyObj then
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

    local plyProps = getPlayerProps( ply )[ply]
    if not plyProps then return end

    local copyObj = PropRestoration.Copy( ply, plyProps )
    if not copyObj then return end

    disconnectedExpireTimes[steamID64] = CurTime() + expireTime

    logger:debug( "Handling (" .. steamID64 .. ")'s props." )

    addPropDataToQueue( ply, props )
end
hook.Add( "PlayerDisconnected", "CFC_Restoration_Disconnect", handleDisconnect, HOOK_HIGH )

local function handleChatCommands( ply, text )
    local exp = string.Explode( " ", text )
    local command = exp[1]

    if command == "!restoreprops" or command == "!proprestore" then
        local steamID64 = ply:SteamID64()

        if canRestoreProps( ply ) then
            if notif then notif:RemovePopups( ply ) end

            if latestDupes[steamID64] then
                spawnInPlayerProps( ply )

                restorationDelays[steamID64] = CurTime() + restoreDelay
                ply:ChatPrint( "Spawning in your props..." )
            else
                ply:ChatPrint( "Couldn't find any props to restore." )
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

            latestDupes[steamID64] = nil
            disconnectedExpireTimes[steamID64] = nil
            file.Delete( restorationDirectory .. "/" .. steamID64 .. ".txt" )
        end
    end

    processSaveQueue()
end )
