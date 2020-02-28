if SERVER then
    AddCSLuaFile( "cfc_prop_restoration/core/cl/cl_init.lua" )
    include( "cfc_prop_restoration/core/sv/sv_init.lua" )
end

if CLIENT then
    include( "cfc_prop_restoration/core/cl/cl_init.lua" )
end
