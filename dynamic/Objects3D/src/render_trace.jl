import GLRenderer as GL
import InverseGraphics as T
import PoseComposition: Pose, IDENTITY_POSE
import Pkg
import FileIO

### Renderer Setup ###

global renderer_is_setup = false
global renderer = nothing
function setup_renderer!()
    YCB_DIR = joinpath(
        Pkg.dir("InverseGraphics"),
        "data"
    );
    world_scaling_factor = 100.
    id_to_cloud, id_to_shift, id_to_box = T.load_ycbv_models_adjusted(YCB_DIR, world_scaling_factor);
    all_ids = sort(collect(keys(id_to_cloud)));
    camera = GL.CameraIntrinsics()
    global renderer = GL.setup_renderer(camera, GL.TextureMode())
    obj_paths = T.load_ycb_model_obj_file_paths(YCB_DIR)
    texture_paths = T.load_ycb_model_texture_file_paths(YCB_DIR)
    for id in all_ids
        mesh = GL.get_mesh_data_from_obj_file(obj_paths[id];tex_path=texture_paths[id])
        mesh = T.scale_and_shift_mesh(mesh, world_scaling_factor, id_to_shift[id])
        GL.load_object!(renderer, mesh)
    end

    global renderer_is_setup = true

    return true
end

### Trace visualization ###

# Once we change to returning noisy images,
# we'll need to update this to pull the latent objects out of the trace
groundtruth_imagelist_of_trace(trace) =
    objectlist_frames_to_images(get_retval(trace))

#=
Each frame is a list of tuples.  Each tuple has the form
(ycb_object_index, position, orientation)
and describes one object.
=#
objectlist_frames_to_images(frames) =
    map(image_of_objectlist, frames)

#=
`objects` is a list of tuples (ycb_object_index, position, orientation).
=#
function image_of_objectlist(objects)
    if !renderer_is_setup
        setup_renderer!()
    end

    (rgb_data, _) = GL.gl_render(renderer,
        map(((id, pos, orn),) -> id, objects),
        map(((id, pos, orn),) -> Pose(pos=collect(pos), orientation=orn), objects),
        IDENTITY_POSE
    )
    return GL.view_rgb_image(rgb_data)
end

to_gif(filename::String, imagelist; fps=5) =
    FileIO.save(
        filename,
        reshape(reduce(hcat, imagelist), (size(imagelist[1])..., :));
        fps
    )