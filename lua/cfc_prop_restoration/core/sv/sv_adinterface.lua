-- https://github.com/wiremod/advdupe2/blob/master/lua/weapons/gmod_tool/stools/advdupe2.lua#L147
local areacopy_classblacklist = {
    gmod_anchor = true
}

local copyPos = Vector( 0, 0, 0 )
local pasteAngle = Angle( 0, 0, 0 )

local function canDupe( ply, ent )
    if not AdvDupe2.duplicator.IsCopyable( ent ) then return false end
    if areacopy_classblacklist[ent:GetClass()] then return false end

    return ent:CPPIGetOwner() == ply
end

local function filterProps( ply, plyProps )
    local filtered = {}

    for _, prop in pairs( plyProps ) do
        if canDupe( ply, prop ) then
            table.insert( filtered, prop )
        end
    end

    return filtered
end

function PropRestoration.Copy( ply, plyProps )
    local toCopy = filterProps( ply, plyProps )

    local entities, constraints = AdvDupe2.duplicator.AreaCopy( toCopy, copyPos, true, ply )
    if next( entities ) == nil then return false end
    return { entities = entities, constraints = constraints }
end

function PropRestoration.Paste( ply, copyObj )
    local entities = copyObj.entities
    local constraints = copyObj.constraints

    ply.AdvDupe2.Entities = entities
    ply.AdvDupe2.Constraints = constraints
    ply.AdvDupe2.Position = copyPos
    ply.AdvDupe2.Angle = pasteAngle
    ply.AdvDupe2.Angle.pitch = 0
    ply.AdvDupe2.Angle.roll = 0
    ply.AdvDupe2.Pasting = true
    ply.AdvDupe2.Name = "Prop restore"
    ply.AdvDupe2.Revision = AdvDupe2.CodecRevision

    AdvDupe2.InitPastingQueue( ply, ply.AdvDupe2.Position, ply.AdvDupe2.Angle, nil, true, true, true, false )
end
