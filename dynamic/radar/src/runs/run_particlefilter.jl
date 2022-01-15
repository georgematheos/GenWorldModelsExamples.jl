using Gen
using GenWorldModels

include("../utils.jl")
include("../model.jl")
T = 5
tr, wt = generate(radar_model, (values(default_params)..., T));
println("Trace generated.  Sampled blips:")
display(get_retval(tr))

include("../visualize.jl")
# (f, t) = get_radar_observation_figure((-100, -100, 100, 100), get_retval(tr))
# (f, t) = get_obs_assmt_figure(
#     (-200, -200, 200, 200),
#     get_retval(tr),
#     trace_to_labeled_tracks(tr)...;
#     labels_title="Ground Truth Assignment"
# )
# f

include("../inference/particle_filter.jl")

n_particles=1000
(inferred_trs, log_weights) = run_particle_filtering(get_retval(tr), getparams(tr), n_particles);
weights = exp.(log_weights .- logsumexp(log_weights))
inferred_trace = inferred_trs[categorical(weights)];

(f, t) = get_obs_assmt_figure(
    (-200, -200, 200, 200),
    get_retval(tr),
    trace_to_labeled_tracks(inferred_trace)...;
    labels_title="Particle Filter -- $n_particles Particles"
)
f
