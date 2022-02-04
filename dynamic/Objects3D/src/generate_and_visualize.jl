include("model.jl")
include("render_trace.jl")
trace, _ = generate(model, (30,));
to_gif("fromtrace.gif", groundtruth_imagelist_of_trace(trace))
