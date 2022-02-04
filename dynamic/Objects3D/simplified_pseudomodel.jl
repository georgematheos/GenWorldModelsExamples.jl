@type Object, Timestep

@oupm household_objects(ROOM_BBOX, VELOCITY_SPACE) begin
    @number Object() ~ poisson(5)

    @property object_type(::Object) ~ categorical(["can", "mustard", ..., "box"])

    @property function position(o::Object, t::Timestep)
        if t == Timestep(1)
            pos ~ uniform3d(ROOM_BBOX)
        else
            posₜ₋₁ = @get position[o, t-1]
            vₜ = @get velocity[o, t]
            pos ~ mvnormal(posₜ₋₁ + vₜ, 0.5 * identity_matrix(3))
        end
        return pos
    end
    @property function velocity(o::Object, t::Timestep)
        if t == Timestep(1)
            vel ~ uniform3D(VELOCITY_SPACE)
        else
            vₜ₋₁ = @get velocity[o, t-1]
            vel ~ mvnormal(vₜ₋₁, 1.0 * identity_matrix(3))
        end
        return vel
    end

    @property function orientation(o::Object, t::Timestep)
        if t == Timestep(1)
            orientation ~ uniform_rot3d()
        else
            orientation ~ vmf_rot3((@get orientation[o, t-1]), 1.0)
        end
        return orientation
    end

    @observation_model function video(T)
        frames = []
        for t = Timestep(1):Timestep(T)
            object_list = [
                (
                    (@get object_type[o]),
                    (@get voxel_shape[o, t]),
                    (@get orientation[o, t])
                )
                for o in @objects(Object)
            ]
            image = render_scene_to_camera(object_list)
            observed_image ~ noisy_image_distribution(image)
            push!(frames, observed_image)
        end

        return frames
    end
end










@property function object_summary(o::Object, t::Timestep)
    return ObjectSummary(
        type        = (@get object_type[o]),
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

@property function observed_image(t::Timestep)
    depth_image = render_scene_to_camera(@get scene_summary_3D[t])
    return noisy_depth_image ~ noisy_image_distribution(depth_image)
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