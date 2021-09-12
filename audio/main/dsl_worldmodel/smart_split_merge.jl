function get_likely_start_end(tr, getprop, isnoise)
    eg = error_gram(tr)
    (ysize, xsize) = size(eg)

    st = max(1, Int(floor(getprop(:onset) * xsize)))
    nd = Int(floor((min(getprop(:onset) + getprop(:duration), 1)) * xsize))

    if nd - st < 1
        return nothing
    end

    if isnoise
        miny, maxy = 1, ysize
    else
        meany = Int(floor(Detector.pos_for_erb_val(getprop(:erb))))
        miny, maxy = max(1, Int(meany - TONESIZE/2)), min(Int(meany + TONESIZE/2), ysize)
    end

    eg_region = eg[miny:maxy, st:nd]
    
    (startsegs, endsegs) = Detector.get_start_end_segs(eg_region)
    if isempty(startsegs) || isempty(endsegs)
        return nothing
    end

    selected_startseg = startsegs[argmax(map(Detector.seglength, startsegs))]
    selected_endseg = endsegs[argmax(map(Detector.seglength, endsegs))]

    (st + selected_endseg.x, st + selected_startseg.x)
end

@kernel function smart_splitmerge_kernel(tr)
    n_tones = @get_number(tr, AudioSource())
    merge_possible = (
      n_tones > 1 &&
      (length([idx for idx = 1:n_tones if @get(tr, is_noise[AudioSource(idx)])]) > 1 ||
        length([idx for idx = 1:n_tones if !@get(tr, is_noise[AudioSource(idx)])]) > 1)
    )
    splitprob = merge_possible ? (n_tones == 4 ? 0. : 0.5) : 1.
    do_split ~ bernoulli(splitprob)

    if do_split
        solo_idx ~ uniform_discrete(1, n_tones)
        deuce_idx1 ~ uniform_discrete(1, n_tones + 1)
        deuce_idx2 ~ uniform_discrete(1, n_tones + 1)
        if deuce_idx1 != deuce_idx2
            prop(addr) = @get(tr, waves[AudioSource(solo_idx)] => addr)
            isnoise = @get(tr, is_noise[AudioSource(solo_idx)])
            if !isnoise
                amp_or_erb1 ~ truncated_normal(prop(:erb), ERB_STD, MIN_ERB, MAX_ERB)
                amp_or_erb2 ~ truncated_normal(prop(:erb), ERB_STD, MIN_ERB, MAX_ERB)
            else
                amp_or_erb1 ~ normal(prop(:amp), AMP_STD)
                amp_or_erb2 ~ normal(prop(:amp), AMP_STD)
            end
            # the split sounds go from prop(:onset) to prop(:onset) + dur1, and
            # startpoint to prop(:onset)+prop(:duration)-dur2 to prop(:onset)+prop(:duration)

            mindur = MIN_DURATION(scene_length)
            likelies = get_likely_start_end(tr, prop, isnoise)
            if likelies !== nothing
                regionsize = size(error_gram(tr))[2]
                likely_start, likely_end = (likelies[1]/regionsize, likelies[2]/regionsize)
                likely_dur_1 = likely_start - prop(:onset)
                likely_dur_2 = (prop(:onset) + prop(:duration)) - likely_end

                dur1 ~ truncated_normal(likely_dur_1, DURATION_STD, mindur, MAX_DURATION(scene_length))
                dur2 ~ truncated_normal(likely_dur_2, DURATION_STD, mindur, MAX_DURATION(scene_length))
            else
                dur1 ~ uniform(mindur, max(mindur + .01, 0.7 * prop(:duration)))
                dur2 ~ uniform(mindur, max(mindur + .01, 0.7 * prop(:duration)))
            end

            updatespec, bwd = split_spec(tr, isnoise, solo_idx, deuce_idx1, deuce_idx2, dur1, dur2, amp_or_erb1, amp_or_erb2)
        else
            updatespec, bwd = EmptyChoiceMap(), choicemap()
        end
    else
        solo_idx ~ uniform_discrete(1, max(1, n_tones - 1))
        deuce_idx1 ~ uniform_discrete(1, n_tones)
        if (deuce_idx1 > n_tones)
          # if this happens, this is the backward step for an impossible forward move;
          # just escape the function quickly in this case
            deuce_idx2 ~ uniform_discrete(1, n_tones)
            updatespec, bwd = EmptyChoiceMap(), choicemap()
        else
            prop1(addr) = @get(tr, waves[AudioSource(deuce_idx1)] => addr)
            isnoise1 = @get(tr, is_noise[AudioSource(deuce_idx1)])
            compatible_indices = [
                idx for idx = 1:n_tones
                if @get(tr, is_noise[AudioSource(idx)]) == isnoise1 && 
                    @get(tr, waves[AudioSource(idx)] => :onset) >= prop1(:onset)
            ]
            deuce_idx2 ~ uniform_from_list(compatible_indices)
            prop2(addr) = @get(tr, waves[AudioSource(deuce_idx2)] => addr)
            
            if deuce_idx1 != deuce_idx2
                if isnoise1
                    amp_or_erb ~ normal((prop1(:amp) + prop2(:amp)) / 2, AMP_STD)
                else
                    amp_or_erb ~ normal((prop1(:erb) + prop2(:erb)) / 2, ERB_STD)
                end

                updatespec, bwd = merge_spec(tr, solo_idx, deuce_idx1, deuce_idx2, amp_or_erb)
            else
                updatespec, bwd = EmptyChoiceMap(), choicemap()
            end
        end
    end

    # add constraints to bwd shared between split and merge
    bwd[:do_split] = !do_split
    bwd[:solo_idx] = solo_idx
    bwd[:deuce_idx1] = deuce_idx1
    bwd[:deuce_idx2] = deuce_idx2
    return (updatespec, bwd)
end

function split_spec(tr, is_noise, old_idx, new_idx1, new_idx2, dur1, dur2, amp_or_erb1, amp_or_erb2)
    old, new1, new2 = map(AudioSource, (old_idx, new_idx1, new_idx2))
    get(addr) = @get(tr, waves[old] => addr)
    set1(addr, val) = @set(waves[new1] => addr, val)
    set2(addr, val) = @set(waves[new2] => addr, val)
    amp_or_erb_addr = is_noise ? :amp : :erb
    return (
        WorldUpdate!(tr,
            Split(old, new1, new2), choicemap(
                @set(is_noise[new1], is_noise), @set(is_noise[new2], is_noise),
                set1(:onset, get(:onset)), set1(:duration, dur1), set2(:duration, dur2),
                set2(:onset, get(:onset) + get(:duration) - dur2),
                set1(amp_or_erb_addr, amp_or_erb1), set2(amp_or_erb_addr, amp_or_erb2)
            )
        ), choicemap((:amp_or_erb, get(amp_or_erb_addr)))
    )
end
function merge_spec(tr, new_idx, old_idx1, old_idx2, amp_or_erb)
    new, old1, old2 = map(AudioSource, (new_idx, old_idx1, old_idx2))
    amp_or_erb_addr = @get(tr, is_noise[old1]) ? :amp : :erb
    get1(addr) = @get(tr, waves[old1] => addr)
    get2(addr) = @get(tr, waves[old2] => addr)
    set(addr, val) = @set(waves[new] => addr, val)
    return (
        WorldUpdate!(tr,
            Merge(new, old1, old2), choicemap(
                @set(is_noise[new], @get(tr, is_noise[old1])),
                set(:onset, get1(:onset)),
                set(:duration, get2(:onset) + get2(:duration) - get1(:onset)),
                set(amp_or_erb_addr, amp_or_erb)
            )
        ), choicemap(
            (:dur1, get1(:duration)), (:dur2, get2(:duration)),
            (:amp_or_erb1, get1(amp_or_erb_addr)), (:amp_or_erb2, get2(amp_or_erb_addr))
        )
    )
end