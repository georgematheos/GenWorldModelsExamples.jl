# GenWorldModelsExamples

This repository contains several examples of inference programs using GenWorldModels.

## Index of Examples

### Most up-to-date models

#### audio
The `audio` folder contains code to infer audio sources underlying an audio file.
See `audio/README.md` for details.  This is the most up-to-date example in the repository.
(The other examples do not use the newest modeling and inference DSLs from GenWorldModels.)

### Less up-to-date models

#### entity-resolution
The `entity-resolution` folder contains an inference program for inferring the entities
described in natural-language text (in particular, a corups of gramatically-parsed New-York-Times articles).

More specifically, this contains a MCMC inference program
for the model described in the paper [Russell et al. 2016 "The Physics of Text: Ontological Realism in Information Extraction"](http://people.eecs.berkeley.edu/~russell/papers/akbc16-pluie.pdf).
We implemented a MCMC program which includes smart-dumb/dumb-smart split/merge moves, as described in the paper,
but we believe we have not implemented exactly the same inference algorithm used in the paper.

This implementation uses old versions of GenWorldModels' modeling and inference languages.
It has not been tested since late 2020.
The model is in [entity-resolution/model2/model2.jl](entity-resolution/model2/model2.jl) and the inference program is in [entity-resolution/inference2/inference.jl](entity-resolution/inference2/inference.jl).
The [audio/experiments/](audio/experiments/) directory includes several experiments we ran.

#### phylogenetics
The `audio` folder contains some very preliminary work on a model for inferring phylogenetic trees.

#### seismic
The `seismic` folder contains a draft of the 1-dimensional seismic monitoring
model from (if my memory serves correctly) a DARPA challenge project.  The problem spec is included in
[seismic/seismic-1D-simplified.docx](seismic/seismic-1D-simplified.docx); I was unable
to find an active link to this online.

#### simpleseismic
The `simpleseismic` folder contains draft code for the highly-simplified seismic moitoring
example used in Figure 1 and 2 of our paper on automating involutive MCMC for open-universe models
using GenWorldModels [Matheos and Lew et al. AABI 2021. "Transforming Worlds: Automated Involutive MCMC
for Open Universe Probabilistic Models"](http://people.eecs.berkeley.edu/~russell/papers/aabi21-oupm.pdf).

This code uses the modeling and inference languages in the state they were in in late 2020 / early 2021 (it
does not use the most up-to-date version of these).