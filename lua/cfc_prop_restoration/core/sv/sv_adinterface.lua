-- https://github.com/wiremod/advdupe2/blob/master/lua/weapons/gmod_tool/stools/advdupe2.lua#L147
local areacopy_classblacklist = {
    gmod_anchor = true
}

local serializer, GroupConstraintOrder

local function getSerializer()
    local name, func = debug.getupvalue( AdvDupe2.Encode, 2 )
    assert( name == "serialize", "Failed to get AdvDupe2's serializer function - did the addon update? (Got: '" .. tostring( name ) .. "')" )

    return func
end

local function getConstraintSorter()
    local outerName, getter = debug.getupvalue( net.Receivers.advdupe2_canautosave, 2 )
    assert( outerName == "GetSortedConstraints", "Failed get AdvDupe2's GetSortedConstraints function - did the addon update? (Got: '" .. tostring( name ) .. "')" )

    local groupOrderName, groupOrder = debug.getupvalue( getter, 1 )
    assert( groupOrderName == "GroupConstraintOrder", "Failed to get AdvDupe2's GroupConstraintOrder function - did the addon update? (Got: '" .. tostring( name ) .. "')" )

    return groupOrder
end

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

    local entities, constraints = AdvDupe2.duplicator.AreaCopy( ply, toCopy, copyPos, true )

    local _, headEnt = next( toCopy )
    if not headEnt then return false end

    local headEntPos = headEnt:GetPos()
    local HeadEnt = {
        Z = headEntPos.z,
        Pos = headEntPos,
        Index = headEnt:EntIndex(),
    }

    return {
        plyName = ply:GetName(), -- For our reference later

        -- Normal Adv2Dupe structure
        HeadEnt = HeadEnt,
        Entities = entities,
        Constraints = constraints,
        Description = "[PropRestoration] Auto save for: " .. tostring( ply ),
        FileMod = CurTime() + GetConVar( "AdvDupe2_FileModificationDelay" ):GetInt(),
    }
end

function PropRestoration.Encode( copyObj, cb )
    -- This encoding happens an indefinite amount of time after the copy
    -- Since a few of these functions need a player, we have to give it stubs instead
    -- (Because the player may not exist anymore at this point)

    local plyStub = {
        -- GroupConstraintOrder only takes a player so it can ChatPrint them
        -- We'll intercept it and print it to server console instead
        ChatPrint = function( msg )
            print( "[PropRestoration] Warning from Adv2 Constraint sorter: ", msg )
        end,

        -- GenerateDupeStamp just wants the player's name
        GetName = function()
            return copyObj.plyName
        end
    }

    copyObj.Constraints = GroupConstraintOrder( plyStub, copyObj.Constraints )
    AdvDupe2.Encode( copyObj, AdvDupe2.GenerateDupeStamp( plyStub ), cb )
end

function PropRestoration.Paste( ply, encodedData )
    local success, dupe = AdvDupe2.Decode( encodedData )
    assert( success, "Failed to decode AdvDupe2 data: " .. ply:SteamID64() )

    local entities = dupe.Entities
    local constraints = dupe.Constraints

    local plyDupe = ply.AdvDupe2
    plyDupe.Entities = entities
    plyDupe.Constraints = constraints
    plyDupe.Position = copyPos
    plyDupe.Angle = pasteAngle
    plyDupe.Angle.pitch = 0
    plyDupe.Angle.roll = 0
    plyDupe.Pasting = true
    plyDupe.Name = "Prop restore"
    plyDupe.Revision = AdvDupe2.CodecRevision

    AdvDupe2.InitPastingQueue( ply, copyPos, pasteAngle, nil, true, true, true, false )
end

hook.Add( "Think", "CFC_PropRestoration_Adv2Setup", function()
    hook.Remove( "Think", "CFC_PropRestoration_Adv2Setup" )

    if not AdvDupe2 then return end

    serializer = serializer or getSerializer()
    GroupConstraintOrder = GroupConstraintOrder or getConstraintSorter()
end )
