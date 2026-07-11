# BioCAP Image Classification Assets

This directory is the install location for the versioned assets Fieldnotes uses
for offline photo identification. The generated assets are deliberately kept out
of normal Git history; only this README and the third-party notice are stored
here in the repository.

Fieldnotes uses BioCAP (`hf-hub:imageomics/biocap`) as a CLIP-style retrieval
model. The app bundles the image encoder and a precomputed matrix representing
the species names it can search. A photo and every species label therefore live
in the same 512-dimensional embedding space, where cosine similarity supplies
the candidate ranking.

Similarity is useful for ranking but is not a calibrated probability or proof
of an exact species identification. Fieldnotes presents multiple candidates and
uses conservative language when the result is ambiguous.

## Install the Production Bundle

From the repository root, run:

```sh
python3 tools/biocap/install_ios_assets.py
```

The installer downloads the pinned archive from the project's GitHub release,
verifies its size and SHA-256, rejects unexpected archive members, verifies all
ten files individually, and only then installs them here. The tracked manifest
is:

```text
tools/biocap/assets/us-regional-v1-state-scope.json
```

The archive is about 262 MB compressed and installs to about 294 MB. It is a
GitHub Release asset rather than a normal repository file because the two large
model artifacts exceed ordinary GitHub file limits and do not belong in every
source-code clone. Earlier GCS build provenance and the full processing history
remain in the tracked tooling and audit evidence.

To install a previously downloaded archive without network access:

```sh
python3 tools/biocap/install_ios_assets.py \
  --archive /path/to/fieldnotes-biocap-us-regional-v1-state-scope.tar.gz
```

## What We Built

The production bundle was assembled in six main stages.

### 1. Build a U.S. animal catalog

`tools/biocap/build_inaturalist_regional_catalog.py` queried iNaturalist's
United States place and its 50 states plus the District of Columbia. The frozen
`us-regional-v1` definition requires research-grade observations with photos,
uses animal taxa, and applies a 2026-06-30 observation cutoff.

The builder resolves current taxonomy, removes duplicate and obsolete taxon
rows, retains replaced names as synonyms, and stores each accepted scientific
name exactly once. The result contains:

- 52,762 active, deduplicated animal species;
- 335,029 state memberships;
- 51 state/D.C. search choices; and
- nine plain-language U.S. regions.

State membership is evidence that a species has been recorded there, not a hard
claim about its complete range. The complete source catalog and API cache are
working data under ignored `tmp/` paths; the compact catalog definition and
audit report are tracked under `tools/biocap/catalogs/`.

### 2. Precompute BioCAP text embeddings

Scientific names were embedded with the official BioCAP/OpenAI zero-shot prompt
ensemble: 81 prompt templates per species, averaged and normalized into one
512-value row. The full U.S. run used a spot L4 worker through SkyPilot and wrote
104 resumable shards, allowing it to recover from two spot preemptions without
starting over.

After download, the canonical matrix was checked against the frozen catalog for
exact scientific-name order, a `52,762 x 512` float32 shape, finite values, and
normalized row norms. Row order is a contract: row `n` in the embedding matrix,
species JSON, and geography file must always describe the same species.

Float16 was also tested. It preserved all 60 top-1 results and all 60 top-ten
candidate sets in the frozen North Carolina comparison, although two queries
reordered near-tied candidates. Fieldnotes currently keeps the canonical
float32 matrix so the shipping baseline is the most directly validated one.

### 3. Export the image encoder to Core ML

The normalized BioCAP vision tower was isolated and converted to a static Core
ML package. The conversion path was compared with the full OpenCLIP model so the
same input image produces a compatible normalized embedding. Fieldnotes applies
the BioCAP/OpenCLIP resize and normalization expected by that encoder.

The iOS classifier currently requests CPU-only Core ML execution. That is the
verified correctness and device-performance baseline for this export; the tested
accelerated configurations were not faster and one simulator configuration
produced invalid zero embeddings.

### 4. Encode geography without duplicating embeddings

The app does not maintain separate state catalogs. `BioCAPGeography.bin` stores
a compact UInt64 state-membership mask for each species row, while state names,
region definitions, and state-to-region mappings live in `BioCAPConfig.json`.

The selected scope simply determines which rows participate in maximum-similarity
search:

- **Automatic:** use the detected state when location is available;
- **State:** search species recorded in the selected state;
- **Region:** combine the states in one of nine broader areas; or
- **All U.S.:** search every bundled species.

If a state or regional search is weak, the interface offers a one-tap All U.S.
retry. This keeps unlikely candidates out of the default result set while still
allowing unusual visitors, travel photos, and incomplete range data to be found.

### 5. Validate ranking and failure behavior

The pipeline was tested with a frozen 60-photo North Carolina field-animal set
covering the Piedmont, mountains, and coast, plus fixture, preprocessing,
catalog-integrity, quantization-parity, and non-animal smoke checks. State-only
subsetting recovered the accuracy lost when the same images were ranked flat
against the entire U.S. catalog, which is why the product defaults to the
detected or selected state instead of applying a small regional score boost.

The 60-photo set is useful regression coverage, not a claim of broad benchmark
quality. More independent regional photos, difficult look-alikes, and open-set
non-animal examples are still needed before treating similarity thresholds as
general confidence calibration. Compact evaluation evidence is tracked under
`tools/biocap/evaluation/`.

### 6. Package a reproducible iOS release

`tools/biocap/package_ios_assets.py` creates one versioned archive and a manifest
containing the exact byte size and SHA-256 of the archive and every member. The
installer performs those checks before replacing local app resources. This keeps
large generated binaries out of Git while making a fresh checkout reproducible.

## Bundled Files

- `Models/BioCAPVisionEncoder.mlpackage` — Core ML BioCAP vision encoder
  (approximately 165 MB).
- `BioCAPTextEmbeddings.f32` — row-major `52,762 x 512` float32 text matrix
  (108,056,576 bytes).
- `BioCAPSpecies.json` — same-order scientific/common-name and taxonomy metadata
  (approximately 26 MB).
- `BioCAPGeography.bin` — compact state-membership mask for every species row.
- `BioCAPConfig.json` — dimensions, prompt/model provenance, and geography
  definitions.
- `THIRD_PARTY_NOTICES.md` — BioCAP model attribution and license.
- `TestFixtures/` — a small image and expected result used by the real Core ML
  integration test.

Current production configuration:

- asset version: `us-regional-v1-state-scope`
- model: `hf-hub:imageomics/biocap`
- species: `52,762`
- embedding dimension and type: `512`, float32
- label text: scientific name
- prompt preset: `biocap-openai` (81 templates)
- geography: 51 state/D.C. choices and nine broader regions

## Runtime Flow

1. The user takes or chooses a photo.
2. The user accepts or adjusts a square subject crop.
3. Fieldnotes resizes and normalizes the crop for BioCAP/OpenCLIP.
4. `BioCAPVisionEncoder.mlpackage` produces a normalized image embedding.
5. Automatic location or the user's Search Area choice selects eligible rows
   through `BioCAPGeography.bin`.
6. The app computes cosine similarity against those text-embedding rows.
7. Species metadata in the matching row supplies the ranked name and taxonomy.
8. Weak local results can be rerun against the complete U.S. catalog.
9. Confirmed photo matches are logged by scientific name so they merge with
   BirdNET audio detections.

The runtime implementation is
`Fieldnotes/Fieldnotes/Services/BioCAPImageClassifier.swift`.

## Rebuilding or Auditing the Assets

The complete workstation workflow, catalog commands, SkyPilot configuration,
evaluation commands, Core ML export, and iOS packaging tools live under:

```text
tools/biocap/
```

Start with `tools/biocap/README.md`. Generated catalogs, downloaded evaluation
photos, API caches, model checkpoints, and intermediate embeddings remain under
ignored `tmp/` paths and are not needed merely to build the iOS app.
