-- Handles the storage of the data

Phoenix.Storage = {
    saveQueue = {},
    saveDir = ""
}

local Storage = Phoenix.Storage

function Storage:ReadDataForPlayer( ply )
    -- TODO: Do this check on the calling side
    if self.playerData[ply:SteamID()] then return end

    local fileName = self.saveDir .. "/" .. ply:SteamID64() .. ".json"
    if not file.Exists( fileName, "DATA" ) then return end

    local contents = file.Read( fileName, "DATA" )
    local decodeData = util.JSONToTable( contents )

    return decodeData
end

function Storage:SaveDataForPlayer( steamID, data )
    local steamID64 = util.SteamIDTo64( steamID )
    local encodeData = util.TableToJSON( data )
    local fileName = self.saveDir .. "/" .. steamID64 .. ".json"

    file.Write( fileName, encodeData )

    local fileSize = string.NiceSize( file.Size( fileName, "DATA" ) )
    logger:info( "Saving prop data to " .. fileName .. " (" .. fileSize .. ")" )
end
