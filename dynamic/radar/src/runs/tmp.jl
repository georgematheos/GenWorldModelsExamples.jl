# (heuristic) distances from detections to objects, with learned parameters θ
dists = Dict(D => [
        dist(θ, D, O) for O in objects(Wₜ₋₁)∪{FalsePositive}
    ] for D in Detectionsₜ
)
Assocₜ = Dict()
for D in Detectionsₜ
    Assocₜ[D] = object ∼ Categorical(normalize(dists[D]))
    if object ≠ FalsePositive
        # set probability of `object` to 0 for all detections
        dists = Dict(D => [O == object ? 0 : dists[D][O] for O in objects] for D in Detectionsₜ)
    end
end




for (objectₜ₋₁, detectionₜ) in Assocₜ
    if objectₜ₋₁ ≠ FalsePositive
        objectₜ.position ~ Normal(
            μ_pos(θ_μ_pos, objectₜ₋₁.position, objectₜ₋₁.velocity, detectionₜ.position),
            σ_pos(θ_σ_pos, objectₜ₋₁.position, objectₜ₋₁.velocity, detectionₜ.position),
        )
        objectₜ.velocity ∼ Normal(
            μ_vel(θ_μ_vel, objectₜ.position, objectₜ₋₁.position, objectₜ₋₁.velocity)
            σ_vel(θ_μ_vel, objectₜ.position, objectₜ₋₁.position, objectₜ₋₁.velocity)
        )
    end
end

# Common pattern: for detected properties,
        # sample new object properties using distributions conditioning
        # on objectₜ₋₁ and detectionₜ, using learned parameters


        # undetected properties can be sampled from other distributions,
        # possibly with learned parameters