using Gen
using GenWorldModels
import GenDirectionalStats

@type Timestep
@type Object

@oupm model(T) begin
    @number (static, diffs) Timestep() = (return @arg(T))

    # In the future we could have the number of aircrafts change over time;
    # for now we will assume it is fixed.
    @number (static, diffs) Object() = (return num ~ poisson(3))

    # Sample the index of the YCB object model for this object
    @property object_type(::Object) ~ uniform_discrete(1, 10)
    
    @property function position(o::Object, t::Timestep)
        if @index(t) == 1
            x ~ uniform(-20, 20)
            y ~ uniform(-20, 20)
            z ~ uniform(70, 80)
        else
            (vxₜ, vyₜ, vzₜ) = @get(velocity[o, t])
            # must explicitly use @abstract here due to bug in GenWorldModels
            (xₜ₋₁, yₜ₋₁, zₜ₋₁) = @get(position[o, @abstract(Timestep(@index(t) - 1))])
            x ~ normal(xₜ₋₁ + vxₜ, 1.5)
            y ~ normal(yₜ₋₁ + vyₜ, 1.5)
            z ~ normal(zₜ₋₁ + vzₜ, 1.5)
        end
        return (x, y, z)
    end

    # [[TODO]]
    @property function velocity(o::Object, t::Timestep)
        return (0., 0., 0.)
    end
    
    # [[TODO: orientation velocity]]
    @property function orientation(o::Object, t::Timestep)
        if @index(t) == 1
            orn ~ GenDirectionalStats.uniform_rot3()
        else
            prev_orn = @get orientation[o, @abstract(Timestep(@index(t) - 1))]
            orn ~ GenDirectionalStats.vmf_rot3(prev_orn, 100)
        end
        return orn
    end

    @observation_model (static) function obs()
        frames = []
        objs = @objects(Object)
        T = @arg(T)
        obj_vec = [Object(i) for i=1:length(objs)]
        time_vec = [Timestep(t) for t=1:T]
        obj_time_pairs = reshape(collect(Iterators.product(obj_vec, time_vec)), (:,))

        types = @map [ @get object_type[obj] for obj in obj_vec ]
        positions = @map [ @get position[o, t] for ((o, t),) in obj_time_pairs ]
        orientations = @map [ @get orientation[o, t] for ((o, t),) in obj_time_pairs ]
    
        return types_pos_orn_to_frames(types, positions, orientations)
    end
end
function types_pos_orn_to_frames(types, positions, orientations)
    result = []
    ctr = 1
    for t=1:length(positions)/length(types)
        this_step = []
        for typ in types
            push!(this_step, (typ, positions[ctr], orientations[ctr]))
            ctr += 1
        end
        push!(result, this_step)
    end
    return result
end
@load_generated_functions()



# for t=1:@arg(T)
#     object_list = [
#         (
#             types[i],
#             (@get position[Object(i), Timestep(t)]),
#             (@get orientation[Object(i), Timestep(t)])
#         )
#         for i=1:length(objs)
#     ]
#     push!(frames, object_list)
# end
# return object_list