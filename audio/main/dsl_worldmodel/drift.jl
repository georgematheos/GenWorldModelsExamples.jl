@dist function uniform_from_list(list)
    idx = uniform_discrete(1, length(list))
    list[idx]
end
singleton(x) = [x]
@dist exactly(x) = singleton(x)[categorical([1.0])]

@gen function duration_drift(tr, i)
    prev_duration = @get(tr, waves[AudioSource(i)] => :duration)
    scene_length = get_args(tr)[1]
    {@addr(waves[AudioSource(i)] => :duration)} ~ truncated_normal(
        prev_duration, DURATION_STD, MIN_DURATION(scene_length), MAX_DURATION(scene_length)
    )
end
@gen function onset_drift(tr, i)
    prev_onset = @get(tr, waves[AudioSource(i)] => :onset)
    scene_length = get_args(tr)[1]
    {@addr(waves[AudioSource(i)] => :onset)} ~ truncated_normal(
        prev_onset, ONSET_STD, MIN_ONSET(scene_length), MAX_ONSET(scene_length)
    )
end
@gen function param_drift(tr, i)
    if @get(tr, is_noise[AudioSource(i)])
        prev_amp = @get(tr, waves[AudioSource(i)] => :amp)
        {@addr(waves[AudioSource(i)] => :amp)} ~ normal(prev_amp, AMP_STD)
    else
        prev_erb = @get(tr, waves[AudioSource(i)] => :erb)
        {@addr(waves[AudioSource(i)] => :erb)} ~ truncated_normal(prev_erb, ERB_STD, MIN_ERB, MAX_ERB)
    end
end
@gen function start_drift(tr, i)
    prev_onset = @get(tr, waves[AudioSource(i)] => :onset)
    prev_duration = @get(tr, waves[AudioSource(i)] => :duration)
    scene_length = get_args(tr)[1]

    new_onset = {@addr(waves[AudioSource(i)] => :onset)} ~ truncated_normal(
        prev_onset, ONSET_STD, MIN_ONSET(scene_length), MAX_ONSET(scene_length)
    )
    old_endtime = prev_onset + prev_duration
    new_duration = old_endtime - new_onset
    {@addr(waves[AudioSource(i)] => :duration)} ~ exactly(new_duration)
end

@gen function switch_source_type(tr, i)
    was_noise = @get(tr, is_noise[AudioSource(i)])
    {@addr(is_noise[AudioSource(i)])} ~ exactly(!was_noise)
    if was_noise
        {@addr(waves[AudioSource(i)] => :erb)} ~ uniform(0.4, 24.0)
    else
        {@addr(waves[AudioSource(i)] => :amp)} ~ normal(10.0, 8.0)
    end
end

function drift_pass(tr)
    for i=1:num_sources(tr)
        tr, _ = mh(tr, duration_drift, (i,))
        tr, _ = mh(tr, onset_drift, (i,))
        tr, _ = mh(tr, param_drift, (i,))
        tr, _ = mh(tr, switch_source_type, (i,))
    end
    return tr
end