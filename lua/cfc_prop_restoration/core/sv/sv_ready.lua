-- Handles the receiving of players' "i'm ready to net message"

util.AddNetworkString( "CFC_Restoration_Ready" )

net.Receive( "CFC_Restoration_Ready", function( _, ply )
    hook.Run( "CFC_Restoration_Ready", ply )
end )
