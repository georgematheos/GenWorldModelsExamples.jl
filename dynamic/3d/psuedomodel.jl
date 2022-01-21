@type Object
@type Timestep

# load pre-learned priors over the voxel grids
# representing the shapes for each type of object
# (e.g. these could be learned by 3DP3)
VOXEL_PRIORS = load_voxel_priors("voxel_priors/")

@oupm household_objects(ROOM_SIZE, MAX_VELOCITY) begin
    @number Object() ~ poisson(5)
    @property object_type(::Object) ~ categorical(["can", "mustard", ..., "box"])

    @property function voxel_shape(o::Object)
        return shape ~ sample_from_voxel_prior(VOXEL_PRIORS, @get object_type[o])
    end

    @property function position(o::Object, t::Timestep)
        if t == Timestep(1)
            x ~ uniform(0, ROOM_SIZE)
            y ~ uniform(0, ROOM_SIZE)
            z ~ uniform(0, ROOM_SIZE)
        else
            (xₜ₋₁, yₜ₋₁, zₜ₋₁) = @get position[o, t-1]
            (vx, vy, vz) = @get velocity[o, t]
            x ~ normal(xₜ₋₁ + vx, 0.5)
            y ~ normal(yₜ₋₁ + vy, 0.5)
            z ~ normal(zₜ₋₁ + vz, 0.5)
        end
        return (x, y, z)
    end
    @property function velocity(o::Object, t::Timestep)
        if t == Timestep(1)
            vx ~ uniform(0, MAX_VELOCITY)
            vy ~ uniform(0, MAX_VELOCITY)
            vz ~ uniform(0, MAX_VELOCITY)
        else
            (vxₜ₋₁, vyₜ₋₁, vzₜ₋₁) = @get velocity[o, t-1]
            vx ~ normal(vxₜ₋₁, 1.0)
            vy ~ normal(vyₜ₋₁, 1.0)
            vz ~ normal(vzₜ₋₁, 1.0)
        end
        return (vx, vy, vz)
    end

    @property function orientation(o::Object, t::Timestep)
        if t == Timestep(1)
            orientation ~ uniform_rot3d()
        else
            # vmf_rot3(center, spread) samples an orientation
            # concentrated around `center`. `spread` controls how
            # concentrated the distribution is around this point
            orientation ~ vmf_rot3((@get orientation[o, t-1]), 1.0)
        end
    end

    @property function object_summary(o::Object, t::Timestep)
        return ObjectSummary(
            shape       = (@get voxel_shape[o]),
            position    = (@get voxel_shape[o, t]),
            orientation = (@get orientation[o, t])
        )
    end
    @property function scene_summary_3D(t::Timestep)
        object_summary_vector = @map [
            @get object_summary[o, t]
            for o in @objects(Object)
        ]
        return Scene3D(object_summary_vector)
    end

    @property function observed_depth_image(t::Timestep)
        depth_image = render_scene_to_camera(@get scene_summary_3D[t])
        return noisy_depth_image ~ depth_image_noise_distribution(depth_image)
    end
end









@property function voxel_grid_for_object_in_room(o::Object, t::Timestep)
    # compute the approximate voxel grid we get by rotating
    # object `o` 
    return get_voxel_grid_for_rotated_object(
        (@get voxel_shape[o]),
        (@get position[o, t]),
        (@get orientation[o, t]),
        (ROOM_SIZE, ROOM_SIZE, ROOM_SIZE)
    )
end
@property function voxel_grid_for_room(t::Timestep)
    return sum(@map_get (
        voxel_grid_for_object_in_room[o, t]
        for t in @objects(Timestep)
    ))
end

@property function observed_depth_image(t::Timestep)
    voxel_grid = @get voxel_grid_for_room[t]
    depth_image = render_voxels_to_camera(voxel_grid)
    return noisy_depth_image ~ depth_image_noise_distribution(depth_image)
end