hook.Add( "InitPostEntity", "CFC_Restoration_Ready", function()
    net.Start( "CFC_Restoration_Ready" )
    net.SendToServer()
end )
