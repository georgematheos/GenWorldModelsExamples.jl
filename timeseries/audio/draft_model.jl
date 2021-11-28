@type Timestep
@type AudioSource

#=
This draft does not yet include the functions for actually producing
the audio waveforms at each point (I am going to copy these
from the old audio model code).
=#

@oupm generate_sounds(
    timestep_length=100 # ms
) begin
    @number AudioSource() ~ uniform_discrete(0, 4)
    @property source_type(::AudioSource) ~
        labeled_categorical([:tone, :noise], [0.6, 0.4])
    

    ### prior over when each source is vs isn't playing ###
    #=
    The prior I've currently included has each audiosource turn on and off
    as a bernoulli process: at each step there is some probability a source
    which is off will turn on, and some probability that a source which is on
    will turn off.  If there is a change of mode, it can happen at any time
    within the timestep window (the exact time of the change is sampled uniformly.)

    We may eventually want to make this distribution more complicated.  For instance,
    we might want to account for sounds switching on and off multiple times per timestep.
    We might want to have a different prior for each one over how likely it is to switch.
    We might want to have different probabilities of turning on vs off.
    We might want to have some notion of the "time signature" of the audio file,
    so that audio sources are likely to turn on and off in a somewhat rhythmic way.
    =#

    # Does this audio source turn on / off at this step?
    @property is_starting_or_ending(a::AudioSource, t::Timestep)
        ~ bernoulli(0.1)

    # IF this audio source is starting/stopping this timestep,
    # how far into the timestep does the change occur?
    @property changepoint_time(a::AudioSource, t::Timestep)
        ~ uniform(0, @arg(timestep_length))
    @property (static) function is_playing_at_end_of_frame(a::AudioSource, t::Timestep)
        if t == Timestep(-1)
            return false
        else
            prev_playing = @get(is_playing_at_end_of_frame[a, t - 1])
            is_changing = @get(is_starting_or_ending[a, t - 1])

            return (prev_playing && !is_changing) || (!prev_playing && is_changing)
        end
    end

    ### dynamics model for sounds ###

    # We can parametrize by different dynamics models for sounds,
    # and have sound-types which are parametrized by different types of properties.
    # On the first pass, I am planning to sample the sound properties on the first
    # timestep and not have them change after that.
    # The intial distribution will be the same as the one used for the AABI paper.
    @property (static) function sound_properties(a::AudioSource, t::Timestep)
        typ = @get(source_type[a])
        if t == Timestep(0)
            props ~ initial_property_prior(typ)
        else
            prevprops = @get(sound_properties[a, t - 1])
            props ~ property_step_prior(prevprops, typ)
        end
        return props
    end

    ### producing waveforms & observations ###

    @property (static) function waves_at_time(a::AudioSource, t::Timestep)
        is_changing = @get(is_playing_at_end_of_frame[a, t])
        change_time = is_changing ? @get(changepoint_time[a, t]) : nothing
        was_playing = @get(is_playing_at_end_of_frame[a, t])
        
        return produce_waves(
            @get(source_type[a]),
            @get(sound_properties[a, t]),
            was_playing,
            change_time
        )
    end

    @property (static) function combined_waves_at_time(t::Timestep)
        # I forget if we are supposed to `sum` the waves, or have some
        # more complicated way of overlaying them; if we need to we can
        # replace `sum` with any function on a set of wave objects
        return sum(
            @setmap (@get waves_at_time[a, t] for a in @objects(AudioSource))
        )
    end

    @property (static) function noisy_waves_at_time(t::Timestep)
        waves = @get(combined_waves_at_time[t])
        noisy ~ noisy_matrix(waves, 1.0)
        return noisy
    end

    @observation_model (static) function produce_audio_file(T)
        timesteps = [Timestep(t) for t=1:T]
        frames = @map [@get(noisy_waves_at_time[t]) for t in timesteps]
        return hcat(frames)
    end
end