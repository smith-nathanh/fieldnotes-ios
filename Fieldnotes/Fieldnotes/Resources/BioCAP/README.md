# BioCAP Image Classification Assets

This directory contains the bundled assets Fieldnotes uses for on-device photo
species identification.

Fieldnotes uses BioCAP (`hf-hub:imageomics/biocap`) as a CLIP-style embedding
model. The app ships only the image side of the model plus a precomputed species
text-embedding matrix. At runtime, the app embeds the user's photo and ranks it
against the bundled species embeddings.

## Runtime Flow

1. The user takes or chooses a photo in the Photo tab.
2. `BioCAPImageClassifier` center-crops and resizes the image to `224x224`.
3. The image is normalized with CLIP/OpenCLIP mean and standard deviation.
4. `BioCAPVisionEncoder.mlpackage` produces a normalized image embedding.
5. The app computes cosine similarity against `BioCAPTextEmbeddings.f32`.
6. The top species rows from `BioCAPSpecies.json` are shown as ranked matches.
7. Saved photo matches are logged by scientific name so they merge with BirdNET
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
- `TestFixtures/` - small fixture image and expected output metadata for app
  validation.

Current asset configuration:

- model: `hf-hub:imageomics/biocap`
- species count: `72,574`
- embedding dimension: `512`
- text label type: scientific name
- prompt preset: `biocap-openai`

## App Integration

The runtime implementation lives in:

```text
Fieldnotes/Fieldnotes/Services/BioCAPImageClassifier.swift
```

The classifier currently loads the Core ML model with CPU compute units for a
conservative baseline. Device performance and accuracy should be measured before
changing compute-unit or quantization choices.

## Related Tooling

The workstation validation/export tooling lives in:

```text
tools/biocap/
```

That tooling README explains how the assets are validated and exported. This
file documents the committed runtime assets that the iOS app loads.
