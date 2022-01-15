singleton(x) = [x]
@dist exactly(x) = singleton(x)[categorical([1.0])]

@type Timestep
@type Aircraft
@type Blip

_binary() = [0, 1]

default_params = (
    mean_num_aircrafts=4,
    detection_prob=0.99,
    false_positive_rate=0.3,
    # The initial x and y positions are ~uniform(-initial_pos_range_scale, initial_pos_range_scale)
    # False positives are also uniform in this range.
    initial_pos_range_scale=100,
    pos_step_std=0.3,
    # the initial x and y vels are ~ uniform(-initial_vel_range_scale, initial_vel_range_scale)
    initial_vel_range_scale=4,
    vel_step_std=0.5,
    obs_std=5
)
@oupm radar_model(
    mean_num_aircrafts, detection_prob, false_positive_rate,
    initial_pos_range_scale, pos_step_std, initial_vel_range_scale, vel_step_std, obs_std,
    T
) begin
    @number (static, diffs) Timestep() = (return @arg(T))

    # In the future we could have the number of aircrafts change over time;
    # for now we will assume it is fixed.
    @number (static, diffs) Aircraft() = (return num ~ poisson(@arg(mean_num_aircrafts)))

    # real blip
    @number (static, diffs) function Blip(a::Aircraft, t::Timestep)
        return num ~ int_bernoulli(@arg(detection_prob))
    end
    # false positive blip
    @number (static, diffs) Blip(::Timestep) = (return num ~ poisson(@arg(false_positive_rate)))
    
    @property function position(a::Aircraft, t::Timestep)
        if @index(t) == 1
           scale = @arg(initial_pos_range_scale)
            x ~ uniform(-scale, scale)
            y ~ uniform(-scale, scale)
        else
            (vxₜ, vyₜ) = @get(velocity[a, t])
            # must explicitly use @abstract here due to bug in GenWorldModels
            (xₜ₋₁, yₜ₋₁) = @get(position[a, @abstract(Timestep(@index(t) - 1))])
            x ~ normal(xₜ₋₁ + vxₜ, @arg(pos_step_std))
            y ~ normal(yₜ₋₁ + vyₜ, @arg(pos_step_std))
        end
        return (x, y)
    end
    @property function velocity(a::Aircraft, t::Timestep)
        if @index(t) == 1
            scale = @arg(initial_vel_range_scale)
            vx ~ uniform(-scale, scale)
            vy ~ uniform(-scale, scale)
        else
            # must explicitly use @abstract here due to bug in GenWorldModels
            (vxₜ₋₁, vyₜ₋₁) = @get(velocity[a, @abstract(Timestep(@index(t) - 1))])
            vx ~ normal(vxₜ₋₁, @arg(vel_step_std))
            vy ~ normal(vyₜ₋₁, @arg(vel_step_std))
        end
        return (vx, vy)
    end

    @property function noisy_position(b::Blip)
        o = @origin(b)
        if length(o) == 2
            # Real detection
            (a, t) = o
            (true_x, true_y) = @get(position[a, t])
            x_reading ~ normal(true_x, @arg(obs_std))
            y_reading ~ normal(true_y, @arg(obs_std))
        else
            # False positive detection
            (t,) = o
            scale = @arg(initial_pos_range_scale)
            x_reading ~ uniform(-scale, scale)
            y_reading ~ uniform(-scale, scale)
        end
        return (x_reading, y_reading)
    end

    @property (static) function blip_readings_at_time(t::Timestep)
        real_blips = @objects(Blip(Aircraft, t))
        fp_blips = @objects(Blip(t))
        blips = union(fp_blips, real_blips)
        
        # set of all readings at this time
        # assume that none of them take the same value, since positions are real values
        readings = @nocollision_setmap (@get(noisy_position[b]) for b in blips)

        return readings
    end

    ## noisy detections observation model
    @observation_model function noisy_detections()
        T = length(@objects(Timestep))
        timesteps = [Timestep(t) for t=1:T]
        readings = @map [@get(blip_readings_at_time[t]) for t in timesteps]
        # include this in the choicemap so we can specify it as evidence and
        # automatically reject any incorrect trace
        for (t, readingset) in enumerate(readings)
            {:_readings => t} ~ exactly(readingset)
        end
        return readings
    end

    ## rendered observation model
    # @property (static) function noisy_image(t::Timestep)
    #     blips = @objects(Blip(Aircraft, t))
    #     readings = @setmap (@get(noisy_position(b)) for b in blips)
    #     perfect_image = render_blips(readings)
    #     noisy_image ~ noisy_matrix(perfect_image)
    #     return noisy_image
    # end
    # @observation_model function noisy_image_model(T)
    #     timesteps = [Timestep(t) for t=1:t]
    #     return @map [@get(noisy_image_model[t]) for t in timesteps]
    # end
end
@load_generated_functions()