using Gen
using GenWorldModels

include("../utils.jl")
include("../model.jl")
include("../visualize.jl")
include("../inference/naive_mh.jl")
include("../inference/particle_filter.jl")

function run_mh_smc(tr, mh_kwargs=(;), particle_filter_kwargs=(;))
    return (run_mh(tr; mh_kwargs...), run_particle_filter(tr; particle_filter_kwargs...))
end

function run_mh(tr; num_iters=100, outdir="videos")
    T = endtime(tr)
    initial_tr = generate_initial_trace_with_correct_number_of_aircrafts(tr);

    (inferred_tr, num_mh_runs) = naive_mh(initial_tr, num_iters, 1);

    (f, t) = get_obs_assmt_figure(
        (-200, -200, 200, 200),
        get_retval(tr),
        trace_to_labeled_tracks(initial_tr)...;
        labels_title="Initial trace"
    )
    record(f, joinpath(outdir, "naive_mh_initial_trace.mp4"), 1:T; framerate=2) do time
        t[] = time
    end

    (f, t) = get_obs_assmt_figure(
        (-200, -200, 200, 200),
        get_retval(tr),
        trace_to_labeled_tracks(inferred_tr)...;
        labels_title="Naive MH -- $num_mh_runs MH Kernel Applications"
    )
    record(f, joinpath(outdir, "naive_mh__$(num_mh_runs)_mh_runs.mp4"), 1:T; framerate=2) do time
        t[] = time
    end

    return (initial_tr, inferred_tr, num_mh_runs)
end

function run_particle_filter(tr; n_particles=100, outdir="videos")
    T = endtime(tr)
    (inferred_trs, log_weights) = run_particle_filtering(get_retval(tr), getparams(tr), n_particles);
    weights = exp.(log_weights .- logsumexp(log_weights))
    inferred_trace = inferred_trs[categorical(weights)];
    
    (f, t) = get_obs_assmt_figure(
        (-200, -200, 200, 200),
        get_retval(tr),
        trace_to_labeled_tracks(inferred_trace)...;
        labels_title="Particle Filter -- $n_particles Particles"
    )
    record(f, joinpath(outdir, "particle_filter__$(n_particles)_particles.mp4"), 1:T; framerate=2) do time
        t[] = time
    end
    
    return (inferred_trs, log_weights)
end

function get_gt_tr(tr=nothing, T=5; outdir="videos")
    if isnothing(tr)
        tr, wt = generate(radar_model, (values(tight_params)..., T), choicemap(@set_number(Aircraft(), 3)));
    end
    (f, t) = get_radar_observation_figure((-200, -200, 200, 200), get_retval(tr))

    record(f, joinpath(outdir, "groundtruth.mp4"), 1:T; framerate=2) do time
        t[] = time
    end

    return tr
end