@type Timestep
@type Aircraft
@type Blip

default_params = (
    mean_num_aircrafts=8,
    detection_prob=0.8,
    false_positive_rate=2,
    initial_pos_std=10.,
    pos_step_std=0.5,
    initial_vel_std=2.,
    vel_step_std=0.8
)
@oupm radar_model(
    mean_num_aircrafts, detection_prob, false_positive_rate,
    initial_pos_std, pos_step_std, initial_vel_std, vel_step_std
) begin
    # In the future we could have the number of aircrafts change over time;
    # for now we will assume it is fixed.
    @number (static, diffs) Aircraft() = (return num ~ poisson(@arg(mean_num_aircrafts)))

    # real blip
    @number (static, diffs) function Blip(a::Aircraft, t::Timestep)
        num ~ bernoulli(@arg(detection_prob))
    end
    # false positive blip
    @number (static, diffs) Blip(::Timestep) = (return num ~ poisson(@arg(false_positive_rate)))
    
    @property function position(a::Aircraft, t::Timestep)
        if @index(t) == 0
            pos ~ normal(0, @arg(initial_pos_std))
        else
            vₜ = @get(velocity[a, t])
            posₜ₋₁ = @get(position[a, Timestep(@index(t) - 1)])
            pos ~ normal(posₜ₋₁ + vₜ, @arg(pos_step_std))
        end
    end
    @property function velocity(a::Aircraft, t::Timestep)
        if @index(t) == 0
            vel ~ normal(0, @arg(initial_vel_std))
        else
            vₜ₋₁ = @get(velocity[a, Timestep(@index(t) - 1)])
            vel ~ normal(vₜ₋₁, @arg(vel_step_std))
        end
    end

    @property (static) function noisy_position(b::Blip)
        (a, t) = @origin(b)
        true_pos = @get(position[a, t])
        reading ~ normal(true_pos, 1.0)
        return reading
    end

    @property (static) function blip_readings_at_time(t::Timestep)
        blips = @objects(Blip(Aircraft, t))
        
        # set of all readings at this time
        # assume that none of them take the same value, since positions are real values
        readings = @nocollision_setmap (@get(noisy_position[b]) for b in blips)
        return readings
    end

    ## noisy detections observation model
    @observation_model function noisy_detections(T)
        timesteps = [Timestep(t) for t=1:T]
        return @map [@get(blip_readings_at_time[t]) for t in timesteps]
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