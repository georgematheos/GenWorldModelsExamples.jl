using Gen
using GenWorldModels
include("model.jl")

T = 4
tr, wt = generate(radar_model, (values(default_params)..., T));
display(get_choices(tr))