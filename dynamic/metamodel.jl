@type Timestep
@type Object
@type Detection

#=
Each concrete model must define:
- NumObjectsPrior
- StaticObjectPropertyPrior
- InitialObjectPropertyPrior
- StepObjectPropertyPrior
- NumFalsePositivesPrior
- NumFalsePositivesPrior
- ObjectDetectionProbability
- DetectedPropertiesPrior
- FalsePositivePropertiesPrior
=#

@oupm model() begin
    @number Object() ~ NumObjectsPrior()

    @property static_properties(::Object) ~ StaticObjectPropertyPrior()
    @property function dynamic_properties(t::Timestep, o::Object)
        if t == Timestep(0)
            static_props = @get(static_properties[o])
            props ~ InitialObjectPropertyPrior(static_props)
        else
            static_props = @get(static_properties[o])
            prev_props = @get(dynamic_props[t - 1, o])
            props ~ StepObjectPropertyPrior(static_props, prev_props)
        end
        return props
    end

    # In a future version we could allow the number of false positives
    # to depend upon the properties of all currently-instantiated objects.
    @number Detection(::Timestep) ~ NumFalsePositivesPrior()
    @number function Detection(t::Timestep, o::Object)
        static_props = @get(static_properties[o])
        current_props = @get(dynamic_props[t - 1, o])
        num ~ bernoulli(ObjectDetectionProbability(static_props, current_props))
        return num
    end

    @property function detected_properties(d::Detection)
        if length(@origin(d)) == 1
            # In a future version we could allow the false-positive properties
            # to depend upon all the currently instantiated objects.
            detected_properties ~ FalsePositivePropertiesPrior()
        else
            # In a future version we could allow the detected properties to depend upon
            # properties of other objects (which might interfere with the detection of this object.)
            static_props = @get(static_properties[o])
            current_props = @get(dynamic_props[t - 1, o])
            detected_properties ~ DetectedPropertiesPrior(static_props, current_props)
        end    
        return detected_properties
    end

    @property function all_detected_properties(t::Timestep)
        detections = union(@objects(Detection(t)), @objects(Detection(t, Object)))
        return @setmap (@get(detected_properties[d]) for d in detections)
    end

    @observation_model function detection_sets_until_time(T)
        timesteps = [Timestep(t) for t=0:T]
        return @map [@get(all_detected_properties(t)) for t in timesteps]
    end
end