# BioCAP Image Classification Assets

This directory contains the bundled assets Fieldnotes uses for on-device photo
species identification.

Fieldnotes uses BioCAP (`hf-hub:imageomics/biocap`) as a CLIP-style embedding
model. The app ships only the image side of the model plus a precomputed species
text-embedding matrix. At runtime, the app embeds the user's photo and ranks it
against the bundled species embeddings.

## Runtime Flow

1. The user takes or chooses a photo in the Photo tab.
2. The user accepts or adjusts an on-device subject crop; the classifier resizes
   that square to `224x224`.
3. The image is normalized with CLIP/OpenCLIP mean and standard deviation.
4. `BioCAPVisionEncoder.mlpackage` produces a normalized image embedding.
5. Automatic location uses the system geocoder to choose a state when possible;
   the user can instead choose a state, broader region, or All U.S.
6. The selected scope filters the eligible embedding rows using
   `BioCAPGeography.bin`, then the app computes cosine similarity only within
   that subset.
7. The top species rows from `BioCAPSpecies.json` are shown as ranked matches.
   Weak state/region results offer a one-tap All U.S. retry.
8. Saved photo matches are logged by scientific name so they merge with BirdNET
   audio detections for the same species.

Scores are cosine similarities, not calibrated probabilities.

## Bundled Files

- `Models/BioCAPVisionEncoder.mlpackage` - Core ML export of the BioCAP vision
  encoder used for image embeddings.
- `BioCAPTextEmbeddings.f32` - row-major float32 text embedding matrix for the
  supported species list.
- `BioCAPSpecies.json` - species metadata in the same row order as the embedding
  matrix. Each row includes scientific name, common name, taxon, and index.
- `BioCAPConfig.json` - shape and provenance metadata for the model assets.
- `BioCAPGeography.bin` - optional compact UInt64 state membership per species;
  present in U.S.-wide regional bundles and interpreted using `BioCAPConfig.json`.
- `TestFixtures/` - small fixture image and expected output metadata for app
  validation.

Current asset configuration:

- model: `hf-hub:imageomics/biocap`
- species count: `52,762` deduplicated U.S. animal species
- geography: `51` state/DC choices and `9` broader U.S. regions
- embedding dimension: `512`
- text label type: scientific name
- prompt preset: `biocap-openai`

## App Integration

The runtime implementation lives in:

```text
Fieldnotes/Fieldnotes/Services/BioCAPImageClassifier.swift
```

The classifier uses CPU-only Core ML execution as the verified safety baseline.
The current converted model produces zero embeddings with `.cpuAndGPU` and `.all`
on the Simulator. Both accelerated configurations preserve top-1 and the top-five
candidate set on the tested iPhone 17 Pro, but were slower than CPU-only in the
cold fixture run. Keep CPU-only for cross-runtime correctness and measured device
performance unless a future export changes those results. Accuracy should also be
measured before changing quantization.

The generated files in this directory are ignored by Git. Restore the pinned
production bundle after a fresh checkout with:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/install_ios_assets.py
```

The installer verifies the tracked archive and every installed file before
replacing the local resources.

## Related Tooling

The workstation validation/export tooling lives in:

```text
tools/biocap/
```

That tooling README explains how the assets are validated and exported. This
file documents the committed runtime assets that the iOS app loads.
