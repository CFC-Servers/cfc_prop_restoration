
net.Receive( "Restore_AlertReconnectingPlayer", function( len )
    -- CREATE NOTIFICATION --
    net.Start( "Restore_RestorePlayerProps" )
    net.SendToServer()
end)