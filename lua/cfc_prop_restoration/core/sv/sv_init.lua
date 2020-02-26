local prop_data = prop_data or {}

local function isValidPlayer( ent )
    return IsValid( ent ) and ent:IsPlayer()
end

local function onEntCreated( ent )
    if not IsValid( ent ) then return end
    if ent:GetClass() ~= "prop_physics" then return end

    local entOwner = ent:GetOwner()
    if not isValidPlayer( entOwner ) then return end

    table.insert( prop_data[entOwner:SteamID64()], ent )
end

hook.Add( "OnEntityCreated", "CFC_Restoration_EntCreate", onEntCreated )

local function onEntRemove( ent )
    if not IsValid( ent ) then return end
    if ent:GetClass() ~= "prop_physics" then return end

    local entOwner = ent:GetOwner()
    if not isValidPlayer( entOwner ) then return end

    table.RemoveByValue( prop_data[entOwner:SteamID64()], ent )
end

hook.Add( "EntityRemoved", "CFC_Restoration_EntRemove", onEntRemove )

local function onPlayerDisconnect( ply )
    prop_data[ply:SteamID64()] = getPlayerProps( ply )
end

hook.Add( "PlayerDisconnected", "CFC_Restoration_Disconnect", onPlayerDisconnect )