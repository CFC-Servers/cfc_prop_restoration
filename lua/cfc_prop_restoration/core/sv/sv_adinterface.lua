ADInterface = {}

local areacopy_classblacklist = {
    gmod_anchor = true
}

local function PlayerCanDupeCPPI( ply, ent )
    if ent.DoNotDuplicate or areacopy_classblacklist[ent:GetClass()] or not IsValid( ent:GetPhysicsObject() ) or not duplicator.IsAllowed( ent:GetClass() ) then return false end
    return ent:CPPIGetOwner() == ply
end

local phys_constraint_system_types = {
    Weld = true,
    Rope = true,
    Elastic = true,
    Slider = true,
    Axis = true,
    AdvBallsocket = true,
    NoCollide = true,
    Motor = true,
    Pulley = true,
    Ballsocket = true,
    Winch = true,
    Hydraulic = true,
    WireMotor = true,
    WireHydraulic = true
}

local function GroupConstraintOrder( ply, constraints )
    --First seperate the nocollides, sorted, and unsorted constraints
    local nocollide, sorted, unsorted = {}, {}, {}
    for k, v in pairs( constraints ) do
        if v.Type == "NoCollide" then
            nocollide[#nocollide + 1] = v
        elseif phys_constraint_system_types[v.Type] then
            sorted[#sorted + 1] = v
        else
            unsorted[#unsorted + 1] = v
        end
    end

    local sortingSystems = {}
    local fullSystems = {}
    local function buildSystems( input )
        while next( input ) ~= nil do
            for k, v in pairs( input ) do
                for systemi, system in pairs( sortingSystems ) do
                    for _, target in pairs( system ) do
                        for x = 1, 4 do
                            if v.Entity[x] then
                                for y = 1, 4 do
                                    if target.Entity[y] and v.Entity[x].Index == target.Entity[y].Index then
                                        system[#system + 1] = v
                                        if #system == 100 then
                                            fullSystems[#fullSystems + 1] = system
                                            table.remove( sortingSystems, systemi )
                                        end
                                        input[k] = nil
                                        goto super_loopbreak
                                    end
                                end
                            end
                        end
                    end
                end
            end

            --Normally skipped by the goto unless no cluster is found. If so, make a new one.
            local k = next( input )
            sortingSystems[#sortingSystems + 1] = { input[k] }
            input[k] = nil

            ::super_loopbreak::
        end
    end
    buildSystems( sorted )
    buildSystems( nocollide )

    local ret = {}
    for _, system in pairs( fullSystems ) do
        for _, v in pairs( system ) do
            ret[#ret + 1] = v
        end
    end
    for _, system in pairs( sortingSystems ) do
        for _, v in pairs( system ) do
            ret[#ret + 1] = v
        end
    end
    for k, v in pairs( unsorted ) do
        ret[#ret + 1] = v
    end

    if #fullSystems ~= 0 then
        ply:ChatPrint( "DUPLICATOR: WARNING, Number of constraints exceeds 100: (" .. #ret .. "). Constraint sorting might not work as expected." )
    end

    return ret
end

local function copyPlayerProps( ply )
    --select all owned props
    local Entities = {}
    for _, ent in pairs( ents.GetAll() ) do
        if PlayerCanDupeCPPI( ply, ent ) then
            Entities[ent:EntIndex()] = ent
        end
    end

    local Ent = Entities[next( Entities )]
    local HeadEnt = {}
    HeadEnt.Index = Ent:EntIndex()
    HeadEnt.Pos = Ent:GetPos()

    local Entities, Constraints = AdvDupe2.duplicator.AreaCopy( Entities, HeadEnt.Pos, true )
    return { Entities, Constraints, HeadEnt }
end

local function pastePlayerProps( ply, data )
    local Entities, Constraints, HeadEnt = unpack( data )

    if ply.AdvDupe2.Pasting or ply.AdvDupe2.Downloading then
        AdvDupe2.Notify( ply, "Advanced Duplicator 2 is busy.", NOTIFY_ERROR )
        return false
    end

    ply.AdvDupe2.HeadEnt = HeadEnt
    ply.AdvDupe2.Entities = Entities
    ply.AdvDupe2.Constraints = GroupConstraintOrder( ply, Constraints )

    ply.AdvDupe2.Pasting = true
    AdvDupe2.InitPastingQueue( ply, nil, nil, ply.AdvDupe2.HeadEnt.Pos, true, true, false, true )
end

ADInterface.copy = copyPlayerProps
ADInterface.paste = pastePlayerProps
