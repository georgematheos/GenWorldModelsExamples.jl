using Serialization, Dates, PyPlot
pygui(true)

#=
Outputs matrices where each column is a run for one initial trace,
and each row represents the ith iteration of each run.
=#
function get_times_and_likelihoods(initial_trs, run_inf!, iters)
    likelihoods = zeros(Float64, (iters, length(initial_trs)))
    times = zeros(Float64, (iters, length(initial_trs)))
    starttime = Dates.now()
    run_inf!(initial_trs[1], 20, (tr,) -> nothing) # compilation run
    for (i, initial_tr) in enumerate(initial_trs)
        print("Running trial $i...;")
        println(" $(Dates.now() - starttime) ms ellapsed in total")
        (l, t, record!) = AudioInference.get_worldmodel_likelihood_time_tracker_and_recorder()
        run_inf!(initial_tr, iters, record!)
        likelihoods[:, i] = l
        times[:, i] = t
    end
    return (times, likelihoods)
end

#=
run_specs should be a Dict{Symbol, <:Tuple{<:Function, <:Real}}
mapping from the name of a run spec to a pair (inference function, num_iters_multiplier)
where the relative `num_iters_multiplier` values specify how many more iterations
to run one inference method for vs another
=#
function perform_runs(run_specs, initial_trs, num_generic_iters)
    times = Dict()
    likelihoods = Dict()
    
    for (label, (inf, num_iters_multiplier)) in run_specs
        n_iters = Int(floor(num_iters_multiplier*num_generic_iters))
        println("Running ", label, " for ", n_iters, " iterations per initial trace.")
        (t, l) = get_times_and_likelihoods(initial_trs, inf, n_iters)
        times[label] = t
        likelihoods[label] = l
    end
    
    return (times, likelihoods)
end

function plot_avg_times_and_likelihoods(times, likelihoods; POINT_SIZE=3, order=nothing, names=nothing, miny=nothing, maxx=nothing)
    key_itr = order === nothing ? keys(times) : order
    for label in key_itr
        t = times[label]
        l = likelihoods[label]
        avg_t = sum(t, dims=2) / size(t)[2]
        avg_l = sum(l, dims=2) / size(l)[2]
        name = names === nothing ? String(label) : names[label]
        scatter(avg_t, avg_l, label=name, s=POINT_SIZE)
    end
    if miny !== nothing
        ylim(bottom=miny)
    end
    if maxx !== nothing
        xlim(right=maxx)
    end
    xlabel("time (s)")
    ylabel("log likelihood of observed sound given inferred sources")
    title("Predictive log-likelihod of inferred audio sources over time")
    legend(loc="lower right")
end

# merges the new times and likelihoods into the running ones (by concatenating to the
# matrix of run data)
# assumes that the same keys are 
function merge_in_runs!(running_times, running_likelihoods, new_times, new_likelihoods)
    for key in keys(running_times)
       running_times[key] = hcat(running_times[key], new_times[key])
       running_likelihoods[key] = hcat(running_likelihoods[key], new_likelihoods[key])
    end
end

### Record data ###
function record_likelihoods!(generate_initial_trs, run_specs, NUM_ITERS;
    filename_prefix=nothing,
    filename=(isnothing(filename_prefix) ? nothing : filename_prefix * Dates.format(Dates.now(), "yyyy-mm-dd--HH-MM-SS")*".jld"),
    running_times=nothing,
    running_likelihoods=nothing,
    num_cycles=1
)
    @assert num_cycles >= 1
    if running_times === nothing || running_likelihoods === nothing
        @assert running_times === nothing && running_likelihoods === nothing "Cannot provide only 1 of running_times and running_likelihoods"
        initial_trs = generate_initial_trs()
        (running_times, running_likelihoods) = perform_runs(run_specs, initial_trs, NUM_ITERS)
        num_cycles -= 1
    else
    @assert size(running_times[:generic])[1] == NUM_ITERS 
    end

    for _=1:(num_cycles)
        if filename !== nothing
            serialize(filename, (times=running_times, likelihoods=running_likelihoods))
        end
        try
            initial_trs = generate_initial_trs()
            (t, l) = perform_runs(run_specs, initial_trs, NUM_ITERS)
            merge_in_runs!(running_times, running_likelihoods, t, l)
        catch e end
    end
    if filename !== nothing
        serialize(filename, (times=running_times, likelihoods=running_likelihoods))
    end

    return (running_times, running_likelihoods, filename)
end
println(record_likelihoods!)