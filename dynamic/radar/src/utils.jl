endtime(tr) = get_args(tr)[end]

function trace_to_labeled_tracks(tr)
    num_objects = @get_number(tr, Aircraft())
    labeled_detections = [[] for t=1:endtime(tr)]
    for t=1:endtime(tr)
        # TODO: false positives
        for a=1:num_objects
            if !isempty(get_submap(get_choices(tr), @addr(position[Aircraft(a), Timestep(t)])))
                push!(
                    labeled_detections[t],
                    (
                        object_idx  = a,
                        xy          = @get(tr, position[Aircraft(a), Timestep(t)]),
                        is_detected = @get_number(tr, Blip(Aircraft(a), Timestep(t)))
                    )
                )
            end
        end
    end

    return(num_objects, labeled_detections)
end