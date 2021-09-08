# This is the top-level testing file as of Sep 7, 2021

using PyPlot
using Dates
include("main.jl")
AI = AudioInference

trr = AI.tones_with_noise(10.); nothing

# println("about to plot_gtg")
# AI.plot_gtg(trr[:kernel => :scene])

# (initial_tr, weight) = AI.generate_initial_tr(trr);
# println("generated initial trace")

function get_avg_likelihoods(initial_trs, run_inf!, iters)
	likelihoods = zeros(Float64, iters)
	times = zeros(Float64, iters)
	starttime = Dates.now()
	run_inf!(initial_tr, 20, (tr,) -> nothing) # compilation run
	for (i, initial_tr) in enumerate(initial_trs)
	  print("Running trial $i...;")
	  println(" $(Dates.now() - starttime) ms ellapsed in total")
	  (l, t, record!) = AudioInference.get_worldmodel_likelihood_time_tracker_and_recorder()
	  run_inf!(initial_tr, iters, record!)
	  likelihoods += l
	  times += t
	end
	likelihoods /= length(initial_trs)
	times /= length(initial_trs)
	return (times, likelihoods)
  end


initial_trs = [AI.generate_initial_tr(trr)[1] for i=1:1]
println("Initial trace generated")

# 	(generic_times, generic_likelihoods) = get_avg_likelihoods(initial_trs, AI.do_generic_inference, 200)
# 	println("did generic inference")
# 	plot(generic_times, generic_likelihoods)

(bd_times, bd_likelihoods) = get_avg_likelihoods(initial_trs, AI.drift_smartbd_inference, 400)
println("did birth/death inference")
plot(bd_times, bd_likelihoods)
