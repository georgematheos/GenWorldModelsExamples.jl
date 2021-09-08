function generic_no_num_change_inference_iter(tr)
    for src in @objects(tr, AudioSource())
        tr, _ = mh(tr, select(@addr(is_noise[src]), @addr(waves[src])))
        if @get(tr, is_noise[src])
            tr, _ = mh(tr, select(@addr(waves[src] => :amp)))
        else
            tr, _ = mh(tr, select(@addr(waves[src] => :erb)))
        end
        tr, _ = mh(tr, select(@addr(waves[src] => :onset)))
        tr, _ = mh(tr, select(@addr(waves[src] => :duration)))
    end
    return tr
end

function generic_inference_iter(tr)
    tr = generic_no_num_change_inference_iter(tr)
    tr, _ = mh(tr, select(@num_addr(AudioSource())))
    return tr
end
  
function do_generic_inference(tr, iters, record_iter!)
    for i = 1:iters
        tr = generic_inference_iter(tr)
        record_iter!(tr)
    end
    return tr
end