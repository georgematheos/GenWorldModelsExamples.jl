@type AudioSource
include("../shared_model.jl")

function combine_scene(waves, scene_duration, audio_sr)
    n_samples = Int(floor(scene_duration * audio_sr))
    scene_wave = reduce(+, waves; init=zeros(n_samples))
    scene_gram, = gammatonegram(scene_wave, wts, audio_sr, gtg_params)
    return (scene_wave, scene_gram)
end

@oupm generate_scene(scene_length, steps, sr) begin
    @number AudioSource() ~ uniform_discrete(0, 4)
    @property is_noise(::AudioSource) ~ bernoulli(0.4)
    @property function waves(s::AudioSource)
        sound_distribution = @get(is_noise[s]) ? generate_single_noise : generate_single_tone
        return {*} ~ sound_distribution(@arg(scene_length), @arg(steps), @arg(sr))
    end
    @observation_model (static) function _generate_scene()
        waves = @map [@get(waves[source]) for source in collect(@objects(AudioSource))]
        scene_wave, scene_gram = combine_scene(waves, @arg(scene_length), @arg(sr))
        scene ~ noisy_matrix(scene_gram, 1.0)
        return (scene_gram, scene_wave, waves)
    end
end
@load_generated_functions()