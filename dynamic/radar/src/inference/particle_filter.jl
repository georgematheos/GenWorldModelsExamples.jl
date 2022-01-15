function run_particle_filtering(observations, params, n_particles)
    obs, obsrest = Iterators.peel(observations)

    println("Beginning to process timestep 1.")
    state = Gen.initialize_particle_filter(
        radar_model, (params..., 1), choicemap((@obsmodel() => :_readings => 1, obs)),
        initial_proposal, (obs, params_to_nt(params)), n_particles
    )

    for (t, obs) in zip(2:length(observations), obsrest)
        println("Beginning to process timestep $t.")
        maybe_resample!(state)
        particle_filter_step!(
            state, (params..., t), ((NoChange() for _ in params)..., UnknownChange()),
            choicemap((@obsmodel() => :_readings => t, obs)),
            step_proposal, (obs, params_to_nt(params), t)
        )
    end

    return (Gen.get_traces(state), Gen.get_log_weights(state))
end

normalize(vec) = vec / sum(vec)
@gen function initial_proposal(obs, params)
    num_aircrafts = {@num_addr(Aircraft())} ~ poisson(params.mean_num_aircrafts)
    {*} ~ sample_nums_and_set_obs([Aircraft(a) for a=1:num_aircrafts], Timestep(1), obs, params)
end
@gen function step_proposal(prevtr, obs, params, T)
    {*} ~ sample_nums_and_set_obs(@objects(prevtr, Aircraft), Timestep(T), obs, params)
end

@gen function sample_nums_and_set_obs(aircrafts, t, obs, params)
    blip_counts = Int[]
    for aircraft in aircrafts
        push!(blip_counts, {@num_addr(Blip(aircraft, t))} ~ int_bernoulli(params.detection_prob))
    end
    num_fps = {@num_addr(Blip(t))} ~ poisson(params.false_positive_rate)

    counts = vcat(blip_counts, [1 for _=1:num_fps])
    if sum(counts) == length(obs)
        for (x, y) in obs
            # untraced randomness.  but even if we were to trace it,
            # the same amount of randomness is used in each proposal,
            # so it would not change the normalized particle weights
            idx = categorical(normalize(counts))
            counts[idx] -= 1

            if idx > length(aircrafts)
                # false positive
                fp_idx = idx - length(aircrafts)
                {@addr(noisy_position[Blip(t, fp_idx)] => :x_reading)} ~ exactly(x)
                {@addr(noisy_position[Blip(t, fp_idx)] => :y_reading)} ~ exactly(y)
            else
                # real blip
                {@addr(noisy_position[Blip((Aircraft(idx), t), 1)] => :x_reading)} ~ exactly(x)
                {@addr(noisy_position[Blip((Aircraft(idx), t), 1)] => :y_reading)} ~ exactly(y)
            end
        end
    end
end