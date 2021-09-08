module AudioInference

using Gen
using GenWorldModels
using WAV
using Dates
include("../tools/plotting.jl")
include("../model/gammatonegram.jl");
include("../model/time_helpers.jl");
include("../model/extra_distributions.jl");

include("dsl_worldmodel/model.jl")
include("dsl_worldmodel/inference.jl")

source_params, steps, gtg_params, obs_noise = include("../params/base.jl")
sr = 2000.0
gtg_params["dB_threshold"] = 0.0
wts, = gtg_weights(sr, gtg_params);
_scene_length = 2.0

args = (_scene_length, steps, sr, wts, gtg_params)

function Base.isapprox(a::Tuple, b::Tuple)
    length(a) == length(b) && all(isapprox(x, y) for (x, y) in zip(a, b))
end
Base.isapprox(a::Symbol, b::Symbol) = a == b

function vis_and_write_wave(tr, title)
    duration, _, sr, = get_args(tr)
    gram, scene_wave, = get_retval(tr)
    wavwrite(scene_wave/maximum(abs.(scene_wave)), title, Fs=sr)
    plot_gtg(gram, duration, sr, 0, 100)
end
function vis_wave(tr)
    duration, _, sr, = get_args(tr)
    gram, scene_wave, = get_retval(tr)
    plot_gtg(gram, duration, sr, 0, 100)
end
plot_gtg(gram) = plot_gtg(gram, _scene_length, sr, 0, 100)

function tones_with_noise(amp)
    cm = choicemap(
        @set_number(AudioSource(), 3),
        @set(is_noise[AudioSource(1)], false),
        @set(waves[AudioSource(1)] => :erb, 10.0),
        @set(waves[AudioSource(1)] => :onset, 0.5),
        @set(waves[AudioSource(1)] => :duration, 0.3),
        @set(is_noise[AudioSource(2)], false),
        @set(waves[AudioSource(2)] => :erb, 10.0),
        @set(waves[AudioSource(2)] => :onset, 1.1),
        @set(waves[AudioSource(2)] => :duration, 0.3),
        @set(is_noise[AudioSource(3)], true),
        @set(waves[AudioSource(3)] => :amp, amp),
        @set(waves[AudioSource(3)] => :onset, 0.8),
        @set(waves[AudioSource(3)] => :duration, 0.3),
    )
    tr, = generate(generate_scene, args, cm)
    return tr
end

function get_worldmodel_likelihood_tracker_and_recorder()
    likelihoods = Float64[]
    function record_worldmodel_iter!(tr)
        push!(likelihoods,
            project(tr, select(@obsmodel() => :scene))
        )
    end
    return (likelihoods, record_worldmodel_iter!)
end
function get_worldmodel_likelihood_time_tracker_and_recorder()
    likelihoods = Float64[]
    times = Float64[]
    starttime = Dates.now()
    function record_worldmodel_iter!(tr)
        push!(likelihoods,
            project(tr, select(@obsmodel() => :scene))
        )
        push!(times, Dates.value(Dates.now() - starttime)/1000)
    end
    return (likelihoods, times, record_worldmodel_iter!)
end

function generate_initial_tr(tr; num_sources=nothing)
    constraints = choicemap((@obsmodel() => :scene, tr[@obsmodel() => :scene]))
    if num_sources !== nothing
        constraints[@obsmodel() => :n_tones] = num_sources
    end
    generate(generate_scene, args, constraints)
end

export tones_with_noise, vis_and_write_wave
export get_worldmodel_likelihood_tracker_and_recorder, generate_initial_tr
export do_generic_inference, drift_smartbd_inference

end