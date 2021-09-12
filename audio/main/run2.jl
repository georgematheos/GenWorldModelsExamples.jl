# WIP new top-level run file as of Sep 9 2021
include("main.jl")
AI = AudioInference
include("experiment_utils.jl")

## record likelihoods on illusion:
run_specs = Dict(
    :lightweight_mh => (AI.do_generic_inference, 1),
    :smart_birthdeath_drift => (AI.drift_smartbd_inference, 1.2),
    :smart_splitmerge_birthdeath_drift => (AI.drift_smartsmbd_inference, .7)
)
NUM_RUNS_PER_EXPERIMENT = 4
trr = AI.tones_with_noise(10.); nothing
(times, likelihoods, _) = record_likelihoods!(
    () -> [AI.generate_initial_tr(trr, num_sources=0)[1] for _=1:NUM_RUNS_PER_EXPERIMENT],
    run_specs, 500;
    filename_prefix="illusion_from_0"
)

plot_avg_times_and_likelihoods(times, likelihoods, POINT_SIZE=1, miny=-300000, maxx=20) 