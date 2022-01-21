-- Handles the receiving of players' "i'm ready to net message"

util.AddNetworkString( "CFC_Phoenix_Ready" )

net.Receive( "CFC_Phoenix_Ready", function( _, ply )
    hook.Run( "CFC_Phoenix_Ready", ply )
end )
