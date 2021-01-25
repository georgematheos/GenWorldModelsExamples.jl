using Gen
using GenWorldModels

abstract type SourceType end
struct Noise <: SourceType end; noise = Noise()
struct Tone <: SourceType end; tone = Tone()
Base.isapprox(a::SourceType, b::SourceType) = a === b

abstract type Action end
struct Birth <: Action
    type::SourceType
    amp_or_erb::Float64
    onset::Float64
    duration::Float64
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
num_sources(tr) = tr[:kernel => :n_tones]
source_type(tr, i) = tr[:world => :waves => AudioSource(i) => :is_noise] ? noise : tone
scene_length(tr) = get_args(tr)[1]
underlying_gram(tr) = get_retval(tr)[1]
observed_gram(tr) = tr[:kernel => :scene]
error_gram(tr) = observed_gram(tr) - underlying_gram(tr)

function birth_for_source_at_idx(tr, i)
    getprop(addr) = tr[:world => :waves => AudioSource(i) => addr]
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

@gen function smart_birth_death_proposal(tr)
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
    end

    # except in a dumb birth move, we need to score our possibilities and select one
    if !do_birth || do_smart_birth
        action_to_score = do_birth ? birth_to_score : death_to_score

        type_to_score = get_type_to_score(action_to_score)
        if isempty(type_to_score)
            println("Doing a $((do_birth ? "birth" : "death")) and have empty type_to_score!")
            println("birth_to_score was $birth_to_score")
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
            {:properties} ~ sample_properties(objtype, action, scene_length(tr))
        else
            # regenerate properties
        end
        idx ~ uniform_discrete(1, num_sources(tr) + 1)
    else
        {:reversing_randomness} ~ sample_death_reversing_randomness(tr, objtype, action)
    end
end

include("../distributions.jl")
@gen function sample_properties(objtype, action::Birth, scene_length)
    if objtype === noise
        amp ~ normal(action.amp_or_erb, AMP_STD)
    else
        erb ~ truncated_normal(action.amp_or_erb, ERB_STD, MIN_ERB, MAX_ERB)
    end

    onset ~ truncated_normal(action.onset, ONSET_STD, MIN_ONSET(scene_length), MAX_ONSET(scene_length))
    duration ~ truncated_normal(action.duration, DURATION_STD, MIN_DURATION(scene_length), MAX_DURATION(scene_length))
end

@gen function sample_death_reversing_randomness(tr, objtype, action::Death)
    possible_births = sample_possible_births(tr, Set(action.idx))
    birth_to_score = Dict(
        b => prob_of_sampling(birth_for_source_at_idx(tr, action.idx), b, scene_length(tr))
        for b in possible_births if b.type == objtype
    )
    
    reverse_smart_prior = reduce(+, values(birth_to_score), init=0.) == 0 ? 0. : SMART_BIRTH_PRIOR
    reverse_is_smart ~ bernoulli(reverse_smart_prior)
    
    if reverse_is_smart
        reverse_birth ~ unnormalized_categorical(birth_to_score)
    end
end

##############
# Involution #
##############

@oupm_involution smart_birth_death_involution (old, fwd) to (new, bwd) begin
    do_birth = @read(fwd[:do_birth], :disc)
    @write(bwd[:do_birth], !do_birth, :disc)
    if do_birth
        do_smart_birth = @read(fwd[:do_smart_birth], :disc)
        @write(bwd[:reversing_randomness => :reverse_is_smart], do_smart_birth, :disc)
        
        idx = @read(fwd[:idx], :disc)
        bwd_action = Death(@read(fwd[:objtype], :disc), idx)
        @write(bwd[:action], bwd_action, :disc)

        source = AudioSource(idx)
        @birth(source)
        @write(new[:kernel => :n_tones], @read(old[:kernel => :n_tones], :disc) + 1, :disc)

        is_noise = @read(fwd[:objtype], :disc) == noise
        @copy(fwd[:objtype], bwd[:objtype])
        @write(new[:world => :waves => source => :is_noise], is_noise, :disc)
        if do_smart_birth
            for addr in (:onset, :duration, (is_noise ? :amp : :erb))
                @copy(fwd[:properties => addr], new[:world => :waves => source => addr])
            end
            @copy(fwd[:action], bwd[:reversing_randomness => :reverse_birth])
        else
            for addr in (:onset, :duration, (is_noise ? :amp : :erb))
                @regenerate(:world => :waves => source => addr)
            end
        end
    else
        rev_smart_birth = @read(fwd[:reversing_randomness => :reverse_is_smart], :disc)
        @write(bwd[:do_smart_birth], rev_smart_birth, :disc)

        death = @read(fwd[:action], :disc)
        is_noise = death.type === noise
        source = AudioSource(death.idx)
        @death(source)
        @write(new[:kernel => :n_tones], @read(old[:kernel => :n_tones], :disc) - 1, :disc)

        @write(bwd[:idx], death.idx, :disc)

        @copy(fwd[:objtype], bwd[:objtype])
        if rev_smart_birth
            for addr in (:onset, :duration, (death.type === noise ? :amp : :erb))
                @copy(old[:world => :waves => source => addr], bwd[:properties => addr])
            end

            @copy(fwd[:reversing_randomness => :reverse_birth], bwd[:action])
        else
            for addr in (:onset, :duration, (is_noise ? :amp : :erb))
                @save_for_reverse_regenerate(:world => :waves => source => addr)
            end
        end
    end
end

smart_birth_death_mh_kern = OUPMMHKernel(smart_birth_death_proposal, (), smart_birth_death_involution)

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

@gen function sample_and_score_possible_births(tr)
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
    waves = (tr[:world => :waves => AudioSource(i)] for i=1:tr[:kernel => :n_tones] if !(i in source_indices_to_ignore))
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
function score(tr, d::Death; threshold=0.3)
    gram = underlying_gram_for_tr_without_indices(tr, Set(d.idx))
    logsc = logpdf(AI.noisy_matrix, observed_gram(tr), gram, 1.0)
    exp(λ * DEATH_DISCOUNT * logsc)

    # corresponding_birth = birth_for_source_at_idx(tr, d.idx)
    # sc = 1/score(tr, corresponding_birth, threshold=threshold)
    # if (
    #     corresponding_birth.type === noise && corresponding_birth.amp_or_erb < 0
    #     || scene_length(tr) - corresponding_birth.onset < 0.1 || corresponding_birth.duration < 0.25
    # )
    #     sc += exp(λ/2)
    # end

    # @assert sc >= 0
    # return sc
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