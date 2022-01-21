-- Handles interaction with the actual data

Phoenix.Data = {
    playerData = {}
}

local Data = Phoenix.Data

function Data:ProcessSaveQueue()
    local steamID, data = next( self.saveQueue )
    if not steamID then return end
    if not data then return end

    logger:debug( "Handling saveQueue for " .. steamID )
    Storage:SaveDataForPlayer( steamID, data )

    self.saveQueue[steamID] = nil
end

