#=
Currently this file contains a baseline MH inference algorithm which does _not_
change the number of aicrafts in the world; we use initial traces which 
have the same number of aircrafts as the world.
We could add (e.g.) a birth/death kernel later to change the number of aircrafts,
but it seemed to me that the inefficiency of naive MH was sufficiently demonstrated
giving the real number of aircrafts that there was no need.
=#

singleton(x) = [x]
@dist exactly(x) = singleton(x)[categorical([1.0])]
@dist uniform_from_list(list) = list[uniform_discrete(1, length(list))]

# Generates an initial trace in which every blip is a false positive.
generate_initial_trace_with_correct_number_of_aircrafts(gt_tr) =
    generate_initial_trace_with_correct_number_of_aircrafts(get_retval(tr), @get_number(gt_tr, Aircraft()), getparams(gt_tr))
function generate_initial_trace_with_correct_number_of_aircrafts(observed_blips, num_aircrafts, model_params)
    initial_tr, _ = generate(radar_model, model_params, choicemap(
        @set_number(Aircraft(), num_aircrafts),
        (
            @set_number(Blip(Aircraft(a), Timestep(t)), false)
            for a=1:num_aircrafts for t=1:length(observed_blips)
        )...,
        (
            @set_number(Blip(Timestep(t)), length(blips))
            for (t, blips) in enumerate(observed_blips)
        )...,
        Iterators.flatten(
            Iterators.flatten(
                (
                    @set(noisy_position[Blip(Timestep(t), i)] => :x_reading, x),
                    @set(noisy_position[Blip(Timestep(t), i)] => :y_reading, y),
                )
                for (i, (x, y)) in enumerate(blips)
            )
            for (t, blips) in enumerate(observed_blips)
        )...
    ))

    return initial_tr
end

# I think this would not work at all, since updating the number
# of blips for an aircraft, or the number of FP blips,
# would always be rejected since it conflicts with the observation.
# So this algorithm cannot change the FPs to be real detections.
# So from the initial traces where everything is an FP, it doesn't work at all.
function lightweight_mh_pass(tr)
    # Update num aircraft
    
    # Update num blips for each aircraft, timestep pair [ALWAYS REJECTED]
    # Update num false positive blips [ALWAYS REJECTED]

    # Update each position[a, t]
    # Update each velocity[a, t]
    
    # Don't update each noisy_position[b]; this is observed
end

function naive_mh_pass(tr)
    T = endtime(tr)
    num_mh_runs = 0
    # Update num aircraft, assigning 0 blips to each aircraft
    # tr, _ = mh(tr, update_num_aircrafts) #update_num_aircrafts, (getparams(tr),))
    
    # Change FP blips to real blips and real blips to FP blips
    for i=1:@get_number(tr, Aircraft())*T / 4
        tr, acc = mh(tr, swap_fp_real; check=false)
        num_mh_runs += 1
    end

    # Update each position[a, t]
    for aircraft in @objects(tr, Aircraft()), t=1:T
        tr, acc = mh(tr, select(@addr(position[aircraft, Timestep(t)])))
        num_mh_runs += 1
    end
    # Update each velocity[a, t]
    for aircraft in @objects(tr, Aircraft()), t=1:T
        tr, acc = mh(tr, select(@addr(velocity[aircraft, Timestep(t)])))
        num_mh_runs += 1
    end

    return (tr, num_mh_runs)
end

function naive_mh(tr, n_iters=1000, log_interval=100)
    println("Beginning naive MH inference...")
    n_mh_runs = 0
    for i=1:n_iters
        (tr, n_runs) = naive_mh_pass(tr)
        n_mh_runs += n_runs
        if i % log_interval == 0
            println("Completed iteration $i.")
        end
    end
    
    return (tr, n_mh_runs)
end

function naive_mh_from_gt(gt_tr, args...; kwargs...)
    tr = generate_initial_trace(gt_tr, getparams(gt_tr))
    return naive_mh(tr, args...; kwargs...)
end

@kernel function swap_fp_real(tr)
    fps = @objects(tr, Blip(Timestep)) |> collect
    real_blip_set = @objects(tr, Blip(Aircraft, Timestep))

    real_blips = collect(real_blip_set)
    there_are_fps = length(fps) > 0
    there_are_non_fps = length(real_blips) > 0

    fp_prob = there_are_fps && there_are_non_fps ? 0.5 : there_are_fps ? 1.0 : 0.0
    flip_fp ~ bernoulli(fp_prob)

    if flip_fp
        fp ~ uniform_from_list(fps)
        (timestep,) = @origin(tr, fp)
        unobserved_aircrafts = filter(@objects(tr, Aircraft)) do aircraft
            !(Blip((aircraft, timestep), 1) in real_blip_set)
        end |> collect    
        if isempty(unobserved_aircrafts)
            # no change
            println("nochange")
            return (EmptyChoiceMap(), choicemap((:flip_fp, true), (:fp, fp)))
        end
        aircraft ~ uniform_from_list(unobserved_aircrafts)
        newblip = Blip((aircraft, timestep), 1)
        (x, y) = @get(tr, noisy_position[fp])
        return (
            WorldUpdate!(tr,
                Delete(fp),
                Create(newblip),
                choicemap(
                    @set(noisy_position[newblip] => :x_reading, x),
                    @set(noisy_position[newblip] => :y_reading, y),
                )
            ),
            choicemap((:flip_fp, false), (:blip, newblip), (:index, @index(tr, fp)))
        )
    else
        blip ~ uniform_from_list(real_blips)
        (aircraft, timestep) = @origin(tr, blip)
        old_num_fps_at_timestep = length([fp for fp in fps if @origin(tr, fp) == (timestep,)])
        index ~ uniform_discrete(1, old_num_fps_at_timestep + 1)
        newblip = Blip((timestep,), index)
        (x, y) = @get(tr, noisy_position[blip])
        return (
            WorldUpdate!(tr,
                Delete(blip),
                Create(newblip),
                choicemap(
                    @set(noisy_position[newblip] => :x_reading, x),
                    @set(noisy_position[newblip] => :y_reading, y),
                )
            ),
            choicemap((:flip_fp, true), (:fp, newblip), (:aircraft, aircraft))
        )
    end
end

### Below is progress on moves to change the number of aircrafts; I didn't finish implementing these.

# @kernel function birth_death_kernel(tr)
#     params = params_to_nt(getparams(tr))
#     T = endtime(tr)
#     num_aircrafts = @get_number(Aircraft(), tr) 
#     do_birth ~ bernoulli(num_aircrafts > 0 ? 0.5 : 1.0)
#     if do_birth
#         idx ~ uniform_discrete(1, num_aircrafts + 1)
#         aircraft = Aircraft(idx)
#         return (
#             WorldUpdate!(tr, Birth(Aircraft(idx)), choicemap(
#                 @set_number(Blip()))
#                 for t=1:T
#             ))
#         )
#     else
#         idx ~ uniform_discrete(1, num_aircrafts)
#     end
# end

# TODO: I'm forgetting why, but this is not correctly reversible.
# I think it should be obvious if I think about
@kernel function update_num_aircrafts(tr)
    params = params_to_nt(getparams(tr))
    T = endtime(tr)
    new_num ~ poisson(params.mean_num_aircrafts)
    old_num = @get_number(tr, Aircraft())

    choices = choicemap(@set_number(Aircraft(), new_num))

    println("new_num = $new_num ; old_num = $old_num")
    if new_num < old_num
        for a=(new_num+1):old_num
            aircraft = Aircraft(a)
            num_new_blips = [0 for _=1:T]
            for blip in @objects(tr, Blip(aircraft, Timestep))
                (_, t) = @origin(tr, blip)
                num_new_blips[t] += 1
                fp_blip = Blip(t, num_new_blips[t])
                choices[@addr(noisy_position[fp_blip])] = @get(tr, noisy_position[blip])
            end
        end
    elseif new_num > old_num
        # set each new aircraft to have 0 blips
        for a=old_num:new_num
            for t=1:T
                aircraft = Aircraft(a)
                timestep = Timestep(t)
                choices[@num_addr(Blip(aircraft, timestep))] = false
            end
        end
    end

    return (choices, choicemap((:new_num, old_num)))
end
