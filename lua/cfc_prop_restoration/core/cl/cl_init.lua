local function restorePlayerProps()
    net.Start( "Restore_RestorePlayerProps" )
    net.SendToServer()
end

net.Receive( "Restore_AlertReconnectingPlayer", function( len )
    -- CREATE NOTIFICATION --
    notif = CFCNotifications.new( "CFC_PropRestorePrompt", "Buttons", true )
    notif:SetTitle( "Restore Props" )
    notif:SetText( "Restore props from previous server save?" )
    notif:AddButton( "Restore", Color(0, 255, 0), "restore" )
    notif:SetTimed( false )
    notif:SetIgnoreable( false )

    function notif:OnButtonPressed( data )
        restorePlayerProps()
    end

    notif:Send()
end )
