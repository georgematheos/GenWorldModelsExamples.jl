using Gen
using GenWorldModels

include("model.jl")
T = 20
tr, wt = generate(radar_model, (values(default_params)..., T));
println("Trace generated.  Sampled blips:")
display(get_retval(tr))

include("utils.jl")
include("visualize.jl")
# (f, t) = get_radar_observation_figure((-100, -100, 100, 100), get_retval(tr))
(f, t) = get_obs_assmt_figure(
    (-100, -100, 100, 100),
    get_retval(tr),
    trace_to_labeled_tracks(tr)...
)
f