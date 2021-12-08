-- Handles the setup of the notifications lib

hook.Add( "CFC_Notifications_init", "CFC_PropRestore_CreateNotif", function()
    logger:debug( "Creating notification object." )

    CFCRestoration.notif = CFCNotifications.new( "CFC_PropRestorePrompt", "Buttons", true )
    notif:SetTitle( "Restore Props" )
    notif:SetText( "Restore props from previous server save?\n(Press the button or use the !restoreprops command)" )
    notif:AddButton( "Restore", Color( 0, 255, 0 ), "restore" )
    notif:SetDisplayTime( restorePromptDuration:GetFloat() )
    notif:SetTimed( true )
    notif:SetIgnoreable( false )

    function notif:OnButtonPressed( ply )
        CFCRestoration.applyPlayerData( ply )
    end
end )
