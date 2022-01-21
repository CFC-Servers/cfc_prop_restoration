hook.Add( "InitPostEntity", "CFC_Phoenix_Ready", function()
    net.Start( "CFC_Phoenix_Ready" )
    net.SendToServer()
end )
