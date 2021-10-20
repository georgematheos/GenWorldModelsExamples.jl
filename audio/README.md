# Inferring Audio Sources from an Audio Scene

This folder contains code for the example in our [2021 AABI Paper](http://people.eecs.berkeley.edu/~russell/papers/aabi21-oupm.pdf)
focused on inferring the audio sources underlying an audio file.
This example is a simplified version of the model from [Cusimano, Hewitt, Tenenbaum, and McDermott, Cogsci 2018, "Auditory scene analysis as Bayesian inference in sound source models"](http://www.mit.edu/~mcusi/basa/mcusi_lbh_basa_summary.pdf).
Maddie Cusimano and Luke Hewitt kindly provided us with their code;
almost all the code in the `model/`, `params/`, and `tools/` directories
were provided by them.

`main/run_inference_performance_comparison.jl` is the most up-to-date top-level script to run inference
in this model.
It runs different inference programs for audio interpretation, and produces plots comparing their performance.
(This produces a version of the plot in Figure 3 of our 2021 AABI paper.)

### File structure

- `demos/` contains some Jupyter notebooks showcasing the model and inference program.  These are not up to date, and use an old version of the inference and modeling DSLs.
- `model/` contains helper code for the audio model.
- `params/` contains hyperparameters.
- `tools/` contains plotting utilities.
- `main/` contains the up-to-date top-level code defining the audio world model and the inference program, as well as the scripts to run inference and produce plots of the inference quality.
  - `main/dsl_worldmodel/model.jl` contains the most up-to-date version of the audio model, using the GenWorldModels modeling DSL as it was as of Oct 12, 2021.
  - `main/dsl_worldmodel/inference.jl` contains the most up-to-date version of the inference code, using the GenWorldModels kernel-writing DSL as it was on Oct 12, 2021.  This includes files containing several different inference kernels (most importantly, `smart_split_merge.jl` and `smart_birth_death.jl`).  The inference DSL used for these is the implemented syntax the inference
  kernel in our ProbProg 2021 poster is based on.
  - `main/old_worldmodel` contains the audio model and inference program as it was at the
  publication of [Matheos and Lew et al, AABI 2021. "Transforming Worlds..."](http://people.eecs.berkeley.edu/~russell/papers/aabi21-oupm.pdf).  This uses older versions of the modeling and inference DSLs.
  - `main/proposal_debugging/` contains some notebooks I used for debugging while writing a heuristic audio-source detector for use within the proposal distributions.
  - `shared_model.jl` contains some code shared by both implementations of the audio model.
  - `main/run_inference_performance_comparison.jl` is the script which runs multiple inference programs and compares their performance.  (This runs the newest implementations.)
  - `main/run.ipynb` and `main/run3.ipynb` are notebooks
  used when producing the plot for the AABI paper.  These implement essentially the same program as `main/run_inference_performance_comparison.jl`.  If I am remembering correctly, `run.ipynb` is the one used for the final plots in the AABI paper.