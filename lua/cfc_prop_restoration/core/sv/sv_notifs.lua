-- Handles the setup of the notifications lib

hook.Add( "CFC_Notifications_init", "CFC_Phoenix_CreateNotif", function()
    logger:debug( "Creating notification object." )

    Phoenix.notif = CFCNotifications.new( "CFC_PhoenixPrompt", "Buttons", true )
    notif:SetTitle( "Restore State" )
    notif:SetText( "Restore state from previous server save?\n(Press the button or use the !phoenix command)" )
    notif:AddButton( "Restore", Color( 0, 255, 0 ), "restore" )
    notif:SetDisplayTime( restorePromptDuration:GetFloat() )
    notif:SetTimed( true )
    notif:SetIgnoreable( false )

    function notif:OnButtonPressed( ply )
        Phoenix.applyPlayerData( ply )
    end
end )
