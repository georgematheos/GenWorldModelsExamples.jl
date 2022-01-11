using GLMakie

set_theme!(theme_dark())

function get_radar_figure(
    (minx, miny, maxx, maxy),
    radar_blips # radar_blips[t] is the set of detected (x, y) positions at time t
)
    points = [[Point2f0(blip) for blip in blips] for blips in radar_blips]

    t = Observable(1)
    f = Figure(resolution=(600,600))
    ax = Axis(f[1, 1], aspect=DataAspect())
    xlims!(ax, (minx, maxx))
    ylims!(ax, (miny, maxy))

    scatter!(ax, @lift(points[$t]), markersize=20, color=:white)

    return (f, t)
end

function animate!(t, T, framerate=2 #= Hz =#)
    for _t = 1:T
        t[] = _t
        sleep(1/framerate)
    end
end