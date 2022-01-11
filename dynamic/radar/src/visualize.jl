using GLMakie
using Colors

set_theme!(theme_dark())

function getax(f, position, (minx, miny, maxx, maxy), title)
    ax = Axis(f[position...]; aspect=DataAspect(), title)
    xlims!(ax, (minx, maxx))
    ylims!(ax, (miny, maxy))
    return ax
end

function plot_radar_observation!(
    ax, t,
    radar_blips # radar_blips[t] is the set of detected (x, y) positions at time t
)
    points = [[Point2f0(blip) for blip in blips] for blips in radar_blips]

    scatter!(ax, @lift(points[$t]), markersize=20, color=:white)
end
function plot_tracked_assignment!(
    ax, fig_t,
    num_objects,
    # labeled_blips[t] is a set of named tuples (object_idx::Int, xy::Tuple{Real, Real}, is_detected::Bool)
    # object_idx is 0 if it is a false-positive detection
    labeled_positions
)
    solid_colors = append!(
        [RGB(.5,.5,.5)], # false positives are gray
        distinguishable_colors(num_objects, [RGB(1,1,1), RGB(0,0,0)], dropseed=true)
    )

    objidx_to_colors = [
        [RGBA(1, 1, 1, 1.0) for _=1:length(labeled_positions)]
        for i=0:num_objects
    ]
    objidx_to_positions = [
        [Vector{Point2f0}() for t=1:length(labeled_positions)]
        for i=0:num_objects
    ]

    for (t, positions) in enumerate(labeled_positions)
        for position in positions
            push!(objidx_to_positions[position.object_idx + 1][t], Point2f0(position.xy))
            alpha = position.is_detected ? 1.0 : 0.3 # fade out undetected aircrafts
            objidx_to_colors[position.object_idx + 1][t] = RGBA(solid_colors[position.object_idx + 1], alpha)
        end
    end

    for (i, (positions, colors)) in enumerate(zip(objidx_to_positions, objidx_to_colors))
        scatter!(
            ax,
            @lift(positions[$fig_t]),
            markersize=20,
            color=@lift(colors[$fig_t]),
            marker=(i == 1 ? :xcross : :circle)
        )
    end
end

function get_radar_observation_figure((minx, miny, maxx, maxy), radar_blips)
    f = Figure(resolution=(600,600))
    t = Observable(1)
    ax = getax(f, (1, 1), (minx, miny, maxx, maxy), "Observed Blips")
    plot_radar_observation!(ax, t, radar_blips)
    return (f, t)
end
function get_obs_assmt_figure((minx, miny, maxx, maxy), radar_blips, num_objects, labeled_blips; labels_title="Ground Truth Assignment")
    f = Figure(resolution=(1200,600))
    obsax = getax(f, (1, 1), (minx, miny, maxx, maxy), "Observed Blips")
    labelax = getax(f, (1, 2), (minx, miny, maxx, maxy), labels_title)
    t = Observable(1)
    plot_radar_observation!(obsax, t, radar_blips)
    plot_tracked_assignment!(labelax, t, num_objects, labeled_blips)
    return (f, t)
end

function animate!(t, T, framerate=2 #= Hz =#)
    for _t = 1:T
        t[] = _t
        sleep(1/framerate)
    end
end