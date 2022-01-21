-- Handles the initial setup of the convars

local logger = Phoenix.logger

if not ConVarExists( "cfc_phoenix_expire_delay" ) then
    logger:debug( "Creating ConVar \"cfc_phoenix_expire_delay\" because it does not exist." )

    CreateConVar(
        "cfc_phoenix_expire_delay",
        600,
        FCVAR_ARCHIVE,
        "Time (in seconds) for the player to reconnect before prop data is lost.",
        0
    )
end

if not ConVarExists( "cfc_phoenix_autosave_delay" ) then
    logger:debug( "Creating ConVar \"cfc_phoenix_autosave_delay\" because it does not exist." )

    CreateConVar(
        "cfc_phoenix_autosave_delay",
        180,
        FCVAR_ARCHIVE,
        "How often (in seconds) the server saves prop data",
        0
    )
end

if not ConVarExists( "cfc_phoenix_notification_timeout" ) then
    logger:debug( "Creating ConVar \"cfc_phoenix_notification_timeout\" because it does not exist." )

    CreateConVar(
        "cfc_phoenix_notification_timeout",
        240,
        FCVAR_ARCHIVE,
        "How long (in seconds) the restore prompt notification will display for players when they join",
        0
    )
end
