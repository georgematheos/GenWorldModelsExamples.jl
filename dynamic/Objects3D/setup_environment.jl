using Pkg

# TODO - get this working
# function setup_production_environment()
#     Pkg.add("git@github.com:georgematheos/Gen.git")
#     Pkg.add("git@github.com:probcomp/DynamicForwardDiff.jl.git")
#     Pkg.add("git@github.com:probcomp/GenTraceKernelDSL.jl.git#")
#     Pkg.add("git@github.com:georgematheos/GenWorldModels.jl.git")
# end

function setup_development_environment_for_georges_laptop()
    Pkg.develop(path="../../../FunctionalCollections.jl/")
    Pkg.develop(path="../../../Gen")
    Pkg.develop(path="../../../DynamicForwardDiff.jl")
    Pkg.develop(path="../../../GenTraceKernelDSL.jl")
    Pkg.develop(path="../../../GenWorldModels.jl")
    Pkg.pkg"dev --local git@github.com:probcomp/MiniGSG.jl.git git@github.com:probcomp/GenDirectionalStats.jl.git git@github.com:probcomp/MeshCatViz.git git@github.com:probcomp/GLRenderer.jl.git";
    Pkg.develop(path="../../../InverseGraphics1.6/InverseGraphics")
end