using Gen
using GenWorldModels

include("utils.jl")
include("model.jl")
T = 20
tr, wt = generate(radar_model, (values(default_params)..., T));
println("Trace generated.  Sampled blips:")
display(get_retval(tr))

include("visualize.jl")
# (f, t) = get_radar_observation_figure((-100, -100, 100, 100), get_retval(tr))
# (f, t) = get_obs_assmt_figure(
#     (-100, -100, 100, 100),
#     get_retval(tr),
#     trace_to_labeled_tracks(tr)...
# )
# f

include("inference/naive_mh.jl")
initial_tr = generate_initial_trace(get_retval(tr), (values(default_params)..., T));

inferred_tr = naive_mh(initial_tr, 200, 1);

(f, t) = get_obs_assmt_figure(
    (-200, -200, 200, 200),
    get_retval(tr),
    trace_to_labeled_tracks(inferred_tr)...
)
f