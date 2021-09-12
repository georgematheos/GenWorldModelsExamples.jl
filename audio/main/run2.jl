# WIP new top-level run file as of Sep 9 2021
include("main.jl")
AI = AudioInference
include("experiment_utils.jl")

## record likelihoods on illusion:
trr = AI.tones_with_noise(10.); nothing
(times, likelihoods, _) = record_likelihoods!(
    () -> [generate_initial_tr(trr, num_sources=0)[1] for _=1:NUM_RUNS_PER_EXPERIMENT],
    run_specs, 500;
    filename_prefix="illusion_from_0"
)

plot_avg_times_and_likelihoods(time, likelihoods, POINT_SIZE=1, miny=-300000)