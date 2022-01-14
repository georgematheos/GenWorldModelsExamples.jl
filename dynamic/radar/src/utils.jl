endtime(tr) = get_args(tr)[end]
getparams(tr) = get_args(tr)[1:end-1]

struct IntBernoulli <: Gen.Distribution{Int} end
const int_bernoulli = IntBernoulli()
Gen.is_discrete(::IntBernoulli) = true
Gen.has_output_grad(::IntBernoulli) = false
Gen.has_argument_grads(::IntBernoulli) = (false, false)
function Gen.random(::IntBernoulli, p)
    Int(bernoulli(p))
end
function Gen.logpdf(::IntBernoulli, val, p)
    Gen.logpdf(bernoulli, Bool(val), p)
end

params_to_nt((
    mean_num_aircrafts, detection_prob, false_positive_rate,
    initial_pos_range_scale, pos_step_std,
    initial_vel_range_scale, vel_step_std, obs_std)) =
    (;
        mean_num_aircrafts, detection_prob, false_positive_rate,
        initial_pos_range_scale, pos_step_std,
        initial_vel_range_scale, vel_step_std, obs_std
    )

function trace_to_labeled_tracks(tr)
    num_objects = @get_number(tr, Aircraft())
    labeled_detections = [[] for t=1:endtime(tr)]
    for t=1:endtime(tr)
        timestep = Timestep(t)
        for blip in @objects(tr, Blip(timestep))
            pos = @get(tr, noisy_position[blip])
            push!(labeled_detections[t],
            (
                object_idx = 0,
                xy = pos,
                is_detected = true
            ))
        end
        for a=1:num_objects
            if !isempty(get_submap(get_choices(tr), @addr(position[Aircraft(a), Timestep(t)])))
                push!(
                    labeled_detections[t],
                    (
                        object_idx  = a,
                        xy          = @get(tr, position[Aircraft(a), Timestep(t)]),
                        is_detected = Bool(@get_number(tr, Blip(Aircraft(a), Timestep(t))))
                    )
                )
            end
        end
    end

    return(num_objects, labeled_detections)
end