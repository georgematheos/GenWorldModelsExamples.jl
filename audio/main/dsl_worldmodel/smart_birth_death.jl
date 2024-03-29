KernelDSL = GenWorldModels.GenTraceKernelDSL

abstract type SourceType end
struct Noise <: SourceType end
struct Tone <: SourceType end
const noise = Noise()
const tone = Tone()
Base.isapprox(a::SourceType, b::SourceType) = a === b

abstract type Action end
struct Birth <: Action
    type::SourceType
    amp_or_erb
    onset
    duration
end
struct Death <: Action
    type::SourceType
    idx::Int
end
Base.isapprox(a::Birth, b::Birth) = (isapprox(a.type, b.type) && isapprox(a.amp_or_erb, b.amp_or_erb) && isapprox(a.onset, b.onset) && isapprox(a.duration, b.duration))
Base.isapprox(a::Death, b::Death) = (isapprox(a.type, b.type) && isapprox(a.idx, b.idx))
Base.isapprox(::Action, ::Action) = false

#################
# Trace getters #
#################
num_sources(tr) = @get_number(tr, AudioSource())
source_type(tr, i) =
    try
        @get(tr, is_noise[AudioSource(i)]) ? noise : tone 
    catch e
        display(get_submap(get_choices(tr), :world))
        throw(e)
    end
scene_length(tr) = get_args(tr)[1]
underlying_gram(tr) = get_retval(tr)[1]
observed_gram(tr::KernelDSL.TraceToken) = KernelDSL.get_undualed(tr, @obsmodel() => :scene)
observed_gram(tr::Gen.Trace) = tr[@obsmodel() => :scene]
error_gram(tr) = observed_gram(tr) - underlying_gram(tr)

function birth_for_source_at_idx(tr, i; need_dual=true)
    getprop(addr) = need_dual ? @get(tr, waves[AudioSource(i)] => addr) : KernelDSL.get_undualed(tr, @addr(waves[AudioSource(i)] => addr))
    type = source_type(tr, i)
    Birth(
        type,
        type === noise ? getprop(:amp) : getprop(:erb),
        getprop(:onset),
        getprop(:duration)
    )
end

############
# Proposal #
############
SMART_BIRTH_PRIOR = 0.9
# how often to randomly choose between birth/death, without looking at the scores?
PROB_RANDOMLY_CHOOSE_BD = 0.1
BIRTH_PRIOR = 0.5
TONESIZE = 10

AMP_STD = 1.0
ERB_STD = 0.5
ONSET_STD = 0.1
DURATION_STD = 0.1

MIN_ERB = 0.4
MAX_ERB = 24
MIN_ONSET = scenelength -> 0.0
MAX_ONSET = scenelength -> scenelength
MIN_DURATION = scenelength -> 0.1
MAX_DURATION = scenelength -> 1.
MAX_NUM_SOURCES = 4
MIN_NUM_SOURCES = 0
NOISE_PRIOR_PROB = 0.4

@kernel function smart_birth_death_kernel(tr)
    # this may involve untraced randomness
    birth_to_score = sample_and_score_possible_births(tr)
    death_to_score = score_possible_deaths(tr)
    
    birthscore, deathscore = reduce(+, values(birth_to_score), init=0.), reduce(+, values(death_to_score), init=0.)
    birthprior = (birthscore) / (birthscore + deathscore)
    birthprior = (birthprior + BIRTH_PRIOR * PROB_RANDOMLY_CHOOSE_BD) / (1 + PROB_RANDOMLY_CHOOSE_BD)
    
    # sample whether to do the birth, factoring in the max and min possible number of objects
    do_birth ~ bernoulli(get_capped_birth_prior(tr, birthprior, birth_to_score))
    if do_birth
        do_smart_birth ~ bernoulli(SMART_BIRTH_PRIOR)
    else
        do_smart_birth ~ exactly(nothing)
    end

    # except in a dumb birth move, we need to score our possibilities and select one
    if !do_birth || do_smart_birth
        action_to_score = do_birth ? birth_to_score : death_to_score

        type_to_score = get_type_to_score(action_to_score)
        if isempty(type_to_score)
            @warn("Doing a $((do_birth ? "birth" : "death")) and have empty type_to_score!")
            @warn("action_to_score was $action_to_score")
        end
        objtype ~ unnormalized_categorical(type_to_score)

        action_to_score = Dict(a => s for (a, s) in action_to_score if a.type == objtype)
        action ~ unnormalized_categorical(action_to_score)
    else
        @assert NOISE_PRIOR_PROB >= 0 && 1 - NOISE_PRIOR_PROB >= 0
        objtype ~ unnormalized_categorical(Dict(noise => NOISE_PRIOR_PROB, tone => (1 - NOISE_PRIOR_PROB)))
    end

    if do_birth
        if do_smart_birth
            proptr ~ sample_properties(objtype, action, scene_length(tr))
        else
            # regenerate properties
        end
        idx ~ uniform_discrete(1, num_sources(tr) + 1)

        return birth_move_spec(tr, idx, do_smart_birth ? action : nothing, objtype == noise, do_smart_birth, do_birth, objtype, do_smart_birth ? proptr : nothing)
    else
        reversing_randomness ~ sample_death_reversing_randomness(tr, objtype, action)
        return death_move_spec(tr, action.idx, objtype, reversing_randomness)
    end
end

function birth_move_spec(tr, idx, birth_action, is_noise, do_smart_birth, do_birth, objtype, properties_tr)
    propval(addr) = KernelDSL.get_undualed(properties_tr, addr)
    src = AudioSource(idx)
    return (
        WorldUpdate!(tr, Create(src), regenchoicemap(
            @set(is_noise[src], is_noise), (
                do_smart_birth ? @set(waves[src] => addr, propval(addr)) :
                                 @regenerate(waves[src] => addr)
                for addr in (:onset, :duration, (is_noise ? :amp : :erb))
            )...
        )), choicemap(
            (:do_birth, !do_birth), (:do_smart_birth, nothing),
            (:reversing_randomness => :reverse_is_smart, do_smart_birth),
            (:reversing_randomness => :reverse_birth, do_smart_birth ? birth_action : nothing),
            (:objtype, objtype), (:action, Death(objtype, idx))
        )
    )
end
function death_move_spec(tr, idx, objtype, reversing_randomness)
    (rev_smart_birth, reverse_birth) = (reversing_randomness[:reverse_is_smart], reversing_randomness[:reverse_birth])
    src = AudioSource(idx)
    bwd_constraints = choicemap(
        (:do_birth, true), (:do_smart_birth, rev_smart_birth),
        (:idx, src.idx), (:objtype, objtype),
        (rev_smart_birth ? (
             (:properties => addr, @get(tr, waves[src] => addr)) 
            for addr in (:onset, :duration, (objtype == noise ? :amp : :erb))
        ) : ())...,
        (:properties => (objtype == noise ? :erb : :amp), nothing),
        (rev_smart_birth ?  ((:action, reverse_birth),) : ())...
    )
    regenerated_in_reverse = rev_smart_birth ? EmptySelection() : select(@addr(waves[src] => addr) for addr in (:onset, :duration, (objtype == noise ? :amp : :erb)))
    return (WorldUpdate!(tr, Delete(src)), (bwd_constraints, regenerated_in_reverse))
end

include("../distributions.jl")
@gen function sample_properties(objtype, action::Birth, scene_length)
    if objtype === noise
        amp ~ normal(action.amp_or_erb, AMP_STD)
        erb ~ exactly(nothing)
    else
        amp ~ exactly(nothing)
        erb ~ truncated_normal(action.amp_or_erb, ERB_STD, MIN_ERB, MAX_ERB)
    end
    onset ~ truncated_normal(action.onset, ONSET_STD, MIN_ONSET(scene_length), MAX_ONSET(scene_length))
    duration ~ truncated_normal(action.duration, DURATION_STD, MIN_DURATION(scene_length), MAX_DURATION(scene_length))
    return (onset, duration, amp, erb)
end

@gen function sample_death_reversing_randomness(tr, objtype, action::Death)
    possible_births = sample_possible_births(tr, Set(action.idx))
    birth_to_score = Dict(
        b => prob_of_sampling(birth_for_source_at_idx(tr, action.idx; need_dual=false), b, scene_length(tr))
        for b in possible_births if b.type == objtype
    )
    
    reverse_smart_prior = reduce(+, values(birth_to_score), init=0.) == 0 ? 0. : SMART_BIRTH_PRIOR
    reverse_is_smart ~ bernoulli(reverse_smart_prior)

    if reverse_is_smart
        reverse_birth ~ unnormalized_categorical(birth_to_score)
    else
        reverse_birth ~ exactly(nothing)
    end
    return (reverse_is_smart, reverse_birth)
end

######################
# Sampling & Scoring #
######################
include("../detector.jl")
function Birth(s::Detector.Source)
    Birth(
        s.is_noise ? noise : tone,
        s.amp_or_erb, s.onset, s.duration
    )
end

function sample_and_score_possible_births(tr)
    Dict(
        b => score(tr, b)
        for b in sample_possible_births(tr)
    )
end
function sample_possible_births(tr, source_indices_to_ignore=Set())
    gram = errorgram_for_tr_without_indices(tr, source_indices_to_ignore)
    detected_sources = Detector.get_detected_sources(gram; scenelength=scene_length(tr), threshold=0.5)
    [Birth(source) for source in detected_sources]
end
function errorgram_for_tr_without_indices(tr, source_indices_to_ignore)
    observed_gram(tr) - underlying_gram_for_tr_without_indices(tr, source_indices_to_ignore)
end
function underlying_gram_for_tr_without_indices(tr, source_indices_to_ignore)
    if isempty(source_indices_to_ignore)
        return underlying_gram(tr)
    end
    (scene_length, steps, sr, wts, gtg_params) = get_args(tr)
    n_samples = Int(floor(scene_length * sr))
    waves = (KernelDSL.get_undualed(tr, @addr(waves[AudioSource(i)])) for i=1:@get_number(tr, AudioSource()) if !(i in source_indices_to_ignore))
    underlying_waves_without_deletion = reduce(+, waves; init=zeros(n_samples))
    gram, = gammatonegram(underlying_waves_without_deletion, wts, sr, gtg_params)
    gram
end

function score_possible_deaths(tr)
    Dict(
        action => score(tr, action)
        for action in (
            Death(source_type(tr, i), i) for i=1:num_sources(tr)
        )
    )
end

# used for scoring
const λ = 2
DEATH_DISCOUNT = 0.000005
"""
    score(tr, d::Death; threshold=0.3)

Score death moves based on the change to the predictive likelihood of the current state after deletion.
"""
# This is 1/score(tr, as_birthmove) -- the inverse of the score we would get for birthing this object now.
# (Another way to put it--this is the same score as the birth score, but with improvement measured
# as (num_less_than_threshold - num_greater_than_threshold)/area).
function score(tr, d::Death)
    gram = underlying_gram_for_tr_without_indices(tr, Set(d.idx))
    logsc = logpdf(noisy_matrix, observed_gram(tr), gram, 1.0)
    return exp(λ * DEATH_DISCOUNT * logsc)
end
"""
    score(tr, b::Birth; threshold=0.3)

The score of a birth action gives a heuristic estimate of how "good" it is to add this object.
This score is calculated by inspecting the rough rectangle in which the tone/noise will be placed,
and counting how many pixels in the errorgram are "on", minus how many are off.  We normalize this by dividing
by the rectangle area, to get a measure of "fraction_improvement"
(what fraction of the area is an improvement, minus the fraction that makes things worse).
The score is e^(λ * improvement).
"""
function score(tr, b::Birth; threshold=0.3)
    ((miny, minx), (maxy, maxx)) = birth_rect(error_gram(tr), b, scene_length(tr))
    gram = @view observed_gram(tr)[miny:maxy, max(1,minx):maxx] # note: we used to only use the error gram for everything in this function
    egram = @view error_gram(tr)[miny:maxy, max(1,minx):maxx]
    maxval = maximum(error_gram(tr))
    greater_than_threshold = gram .> maxval * threshold
    less_than_threshold = gram .< maxval * threshold
    area = (maxx - minx + 1) * (maxy - miny + 1)
    improvement = (sum(greater_than_threshold) - sum(less_than_threshold))/area
    score = exp(λ * improvement)
    @assert score >= 0
    return score
end

##################
# Util functions #
##################

function get_type_to_score(action_to_score)
    tts = Dict()
    for (act, score) in action_to_score
        tp = act.type
        tts[tp] = get(tts, tp, 0) + score
        if tts[tp] < 0
            println("Just made a score negative when adding in $score")
        end
    end
    return tts
end

function get_capped_birth_prior(tr, prior, birth_possibilities)
    if num_sources(tr) >= MAX_NUM_SOURCES || isempty(birth_possibilities)
        0.
    elseif num_sources(tr) <= MIN_NUM_SOURCES 
        1.
    else
        prior
    end
end

"""
    prob_of_sampling(output::Birth, detected::Birth, scenelength)

The PDF of the proposal sampling the object represented by `output` after selecting birth action `detected`.
"""
function prob_of_sampling(output, detected, scenelength)
    (weight, _) = assess(sample_properties, (output.type, detected, scenelength), choicemap(
        (output.type == noise ? :amp : :erb) => output.amp_or_erb,
        (output.type == noise ? :erb : :amp) => nothing,
        :onset => output.onset,
        :duration => output.duration
    ))
    return exp(weight)
end

function birth_rect(img, birth::Birth, scenelength)
    xwidth = size(img)[2]
    start = Int(floor(birth.onset/scenelength * xwidth))
    dur = Int(floor(birth.duration/scenelength * xwidth))
    xmin, xmax = start, min(start + dur, xwidth)
    if birth.type === tone
        y = Int(floor(Detector.pos_for_erb_val(birth.amp_or_erb)))
        ymin, ymax = max(1, y-Int(TONESIZE/2)), min(size(img)[1], y+Int(TONESIZE/2))
    else
        ymin, ymax = 1, size(img)[1]
    end
    return ((ymin, xmin), (ymax, xmax))
end