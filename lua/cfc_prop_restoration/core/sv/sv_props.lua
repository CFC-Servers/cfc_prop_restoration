-- Handles prop interactions. Finding, recording, etc.

local pcall = pcall
local rawget = rawget
local rawset = rawset
local IsValid = IsValid
local insert = table.insert

local function getAllPropsByPlayer()
    local playerProps = {}

    for _, ply in ipairs( player.GetHumans() ) do
        playerProps[ply] = {}
    end

    local ents = ents.GetAll()
    local entsCount = #ents

    for i = 1, entsCount do
        local prop = rawget( ents, i )

        if IsValid( prop ) then
            local propOwner = prop:CPPIGetOwner()

            if IsValid( propOwner ) then
                insert( playerProps[propOwner], prop )
            end
        end
    end

    return playerProps
end

local function getEntityRestorers( ents )
    if not ents then return {} end
    local restorers = {}
    local entCount = #ents

    for i = 1, entCount do
        local ent = rawget( ents, i )

        if IsValid( ent ) then
            local physObj = ent:GetPhysicsObject()
            physObj = IsValid( physObj ) and physObj

            local velocity, angVelocity

            if physObj then
                velocity = physObj:GetVelocity()
                angVelocity = physObj:GetAngleVelocity()
            end

            rawset( restorers, i, function()
                physObj:SetVelocity( velocity )
                physObj:SetAngleVelocity( angVelocity )
            end )
        else
            rawset( restorers, i, noop )
        end
    end

    return restorers
end

local function runRestorers( restorers )
    if not restorers then return end
    local restorerCount = #restorers

    for i = 1, restorerCount do
        pcall( rawget( restorers, i ) )
    end
end
