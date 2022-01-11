## Runtime inference loop
Inference will alternate two phases:
1. Incorporating new detections
2. Rejuvenating the currently inferred traces

### Rejuvenating the currently inferred traces
For a concrete model, there will be several types of proposals
for use in rejuvenation moves:

Rejuvenation moves for an individual object:
1. Re-propose an object's static properties based on all the dynamic properties
2. Re-propose an object's dynamic properties at a single timestep based on
   the surrounding dynamic properties, the static properties, and (if applicable) the
   detection of that object at that timestep
We may want some way for the inference algorithm to be able to block these types of
moves together, and (e.g.) re-propose multiple timesteps' dynamic properties at once, or the static
properties at the same time as several timesteps' dynamic properties.

Rejuvenation moves for data-assocation:
- Reassociate detection at a timestep
- Split object + distribute all detections
- Merge object + associate all old detections with merged object (or maybe set some as FPs)
- Create object + reassociate detections to it
- Delete object + reassociate detections from it

## Training

### Tuning parameters in the inference proposals
The proposals for object properties can include parameters for the inference
algorithm to automatically optimize to make the proposal close to a
posterior under the model.
(Question: does our architecture specify what the posterior is?
Or are there some degrees of freedom regarding what the proposal
is conditional on that the users can specify?  These degrees of
freedom may require some adjustment in terms of how we do amortized inference.)

Probably it is simplest to do this for proposals which cannot
condition on variables in the trace which are getting proposed-to
(since then it's obvious what posterior we want to be approximating).

Tuning for these parameters can occur offline by generating data from the model.
(Question: can it also occur online, using the particular observed traces?
Is there a benefit to both doing online and offline training?)

### Free parameters in the models
The user can also leave some parameters in the model free (e.g.
the false-positive rate).  We can optimize these by approximately maximizing
the data likelihood conditioned on the inferred particle clouds.

