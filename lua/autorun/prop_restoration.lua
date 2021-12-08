if SERVER then
    include( "cfc_prop_restoration/core/sv/sv_adinterface.lua" )
    include( "cfc_prop_restoration/core/sv/sv_ready.lua" )
    include( "cfc_prop_restoration/core/sv/sv_init.lua" )

    AddCSLuaFile( "cfc_prop_restoration/core/cl/cl_ready.lua" )
else
    include( "cfc_prop_restoration/core/cl/cl_ready.lua" )
end
