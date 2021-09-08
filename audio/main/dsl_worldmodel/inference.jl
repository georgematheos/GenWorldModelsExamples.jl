include("generic_inference.jl")
include("drift.jl")
include("smart_birth_death.jl")
include("smart_split_merge.jl")

function drift_smartbd_iter(tr)
    tr, _ = mh(tr, smart_birth_death_kernel; check=false)
    tr = drift_pass(tr)
    return tr
end

function drift_smartbd_inference(tr, iters, record_iter! = identity)
    for _=1:iters
        tr = drift_smartbd_iter(tr)
        record_iter!(tr)
    end
    return tr
end

# function splitmerge(tr)
#     tr, acc = metropolis_hastings(tr, smart_splitmerge_mh_kern; check=false)#, logfwdchoices=true, logscores=true)
#     return tr
# end

# function drift_smartsmbd_iter(tr)
#     tr, _ = mh(tr, smart_birth_death_mh_kern; check=false)
#     tr = drift_pass(tr)
#     tr = splitmerge(tr)
#     return tr
# end

# function drift_smartsmbd_inference(tr, iters, record_iter! = identity)
#     for _=1:iters
#         tr = drift_smartsmbd_iter(tr)
#         record_iter!(tr)
#     end
#     return tr
# end