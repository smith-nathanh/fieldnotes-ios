# BioCAP Phase 0 Validation

This directory is for workstation validation and the narrow iOS integration
spike. It does not wire BioCAP into the product UI.

The goal is to prove the deployment assumption from `BIOCAP-MODEL.md`:

- run the full BioCAP/OpenCLIP model on images and species names;
- precompute text embeddings once, save and reload them;
- use the cached text matrix with the image encoder and get the same top-k;
- isolate the vision tower and verify its normalized embedding matches
  `model.encode_image`;
- optionally export that normalized vision tower to Core ML and compare output.

## Setup

Use `uv` with Python 3.11 or 3.12. The system `python3` in this checkout may be
too new for PyTorch/Core ML packages.

```sh
uv venv --python 3.12 .venv-biocap
uv pip install --python .venv-biocap/bin/python -r tools/biocap/requirements.txt
```

The first BioCAP run downloads `imageomics/biocap` from Hugging Face through
OpenCLIP, so network access and Hugging Face cache space are required.

The requirements intentionally pin Torch to the newest version tested by
coremltools for this converter path. Newer Torch releases may trace attention
into frontend ops that coremltools cannot lower.

## Install the Versioned iOS Assets

Generated model and catalog files are intentionally ignored by Git. A fresh
checkout can install the exact production bundle from GCS with:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/install_ios_assets.py
```

The tracked `assets/nc-regional-birdnet-travel-v2.json` manifest verifies the
191,588,494-byte archive SHA-256, rejects unexpected archive members, then
verifies the size and SHA-256 of all eight model, catalog, and fixture files.
Pass `--archive` to verify and install an existing download without GCS access.

To package a future validated release:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/package_ios_assets.py \
  --input-dir Fieldnotes/Fieldnotes/Resources/BioCAP \
  --version nc-regional-birdnet-travel-v2 \
  --gcs-uri gs://fieldnotes-biocap/ios-assets/nc-regional-birdnet-travel-v2/fieldnotes-biocap-nc-regional-birdnet-travel-v2.tar.gz \
  --archive tmp/biocap-ios-assets/fieldnotes-biocap-nc-regional-birdnet-travel-v2.tar.gz \
  --manifest tools/biocap/assets/nc-regional-birdnet-travel-v2.json
```

Use a normal non-composite GCS upload for this distributable. The tracked
production object has GCS CRC32C and MD5 metadata in addition to the
installer-enforced SHA-256.

## North Carolina Product Baseline

The versioned `nc-v1` benchmark is the product-facing field-animal baseline. Its
definition freezes exact iNaturalist observation/photo IDs for 30 taxa across
Charlotte/Piedmont, the mountains, and the coast. It covers 15 animal groups.
It measures catalog coverage when labels are absent, but it is not a negative
open-set benchmark because every input is an animal photo.
Images remain ignored under `tmp/`; attribution metadata is retained beside
them. Review iNaturalist terms and the individual photo licenses before running:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/prepare_nc_evaluation.py \
  --accept-terms \
  --output-dir tmp/biocap-datasets/nc-v1
```

Classify the frozen set against the untouched 72,574-row catalog:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/classify_biocap_cached.py \
  --embeddings tmp/biocap-validation/cloud-l4-animal-only/biocap_text_embeddings.npz \
  --species-list tmp/biocap-validation/cloud-l4-animal-only/image-field-animals-no-plants-fungi-species.jsonl \
  --image-manifest tmp/biocap-datasets/nc-v1/benchmark_manifest.jsonl \
  --device cpu \
  --top-k 10 \
  --output tmp/biocap-validation/nc-v1-global-72574/rankings.csv \
  --report tmp/biocap-validation/nc-v1-global-72574/baseline_report.json
```

The runner refuses to score an archive whose embedded scientific-name order
does not exactly match the species list. Its report separates overall accuracy
from accuracy among in-catalog labels, because missing species must count as a
product failure. It also reports genus/family accuracy, reciprocal rank,
group/region slices, forced predictions on out-of-catalog images, timing, and
process peak RSS. The checked-in compact result is
`evaluation/nc-v1-baseline-72574.json`; detailed per-image output remains under
ignored `tmp/`.

Build the source-derived regional catalog candidate:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/build_inaturalist_regional_catalog.py \
  --output tmp/biocap-catalogs/nc-regional-v1/species.jsonl \
  --report tmp/biocap-catalogs/nc-regional-v1/report.json
```

The catalog definition freezes North Carolina place ID 30, a 2026-06-30
cutoff, research-grade observations, and all animal iconic taxa. API pages and
taxonomy batches are cached under ignored `tmp/` paths. The checked-in audit is
`catalogs/nc-regional-v1-report.json`.

Build the U.S.-wide regional source catalog:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/build_inaturalist_regional_catalog.py \
  --definition tools/biocap/catalogs/us-regional-v1.json \
  --output tmp/biocap-catalogs/us-regional-v1/species.jsonl \
  --report tmp/biocap-catalogs/us-regional-v1/report.json \
  --cache-dir tmp/biocap-catalogs/inaturalist-us-cache
```

`us-regional-v1` uses the United States parent place, requires research-grade
observations with photos, and freezes a 2026-06-30 cutoff. It stores every
species once, then joins observation membership for the 50 states and District
of Columbia onto that row. The state records are grouped into nine plain-language
areas for product use: Northeast, Southeast, Midwest, South Central, Southwest,
Mountain West, Pacific, Alaska, and Hawaii. Territories are deliberately deferred
rather than being silently assigned to an incorrect area.

State and area membership are ranking context, not separate catalogs and not a
hard range boundary. Future iOS export should encode the membership compactly;
there must still be exactly one text embedding per scientific name. A quick
source/taxonomy smoke test can skip the membership crawl:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/build_inaturalist_regional_catalog.py \
  --definition tools/biocap/catalogs/us-regional-v1.json \
  --output tmp/biocap-catalogs/us-regional-v1-smoke/species.jsonl \
  --report tmp/biocap-catalogs/us-regional-v1-smoke/report.json \
  --cache-dir tmp/biocap-catalogs/inaturalist-us-cache \
  --max-pages 1 \
  --skip-memberships \
  --sleep-seconds 0
```

All API pages and taxonomy batches are cached. Re-running the full command after
an interruption resumes from those files and still rebuilds the final catalog
deterministically.

The completed source build contains 52,762 active species and the same number of
unique iNaturalist taxon IDs. It records 335,029 state memberships with no species
left outside the 50-state/D.C. membership set. A final current-taxonomy pass
replaced five obsolete rows discovered during the long paged crawl and retained
their former names as synonyms. The checked-in compact audit is
`catalogs/us-regional-v1-report.json`; the 35,559,460-byte source JSONL remains
under ignored `tmp/` paths and is pinned by SHA-256 in that report.

At 512 dimensions, the full matrix is projected to use 108,056,576 bytes as
float32 or 54,028,288 bytes as float16. These are projections only. Float16 must
preserve ranking parity before the U.S. catalog can replace production assets.

To build the optional travel tier, first enrich missing hierarchy in the older
global species list, then merge only BirdNET-linked rows that have validated
taxonomy:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/enrich_fallback_taxonomy.py \
  --species-list tmp/biocap-validation/cloud-l4-animal-only/image-field-animals-no-plants-fungi-species.jsonl \
  --inaturalist-map tmp/biocap-validation/cloud-l4-animal-only/inaturalist-common-names.jsonl \
  --output tmp/biocap-catalogs/fallback-taxonomy/image-field-animals-enriched.jsonl \
  --report tmp/biocap-catalogs/fallback-taxonomy/report.json

uv run --python .venv-biocap/bin/python tools/biocap/merge_biocap_embedding_catalogs.py \
  --regional-embeddings tmp/biocap-catalogs/nc-regional-v1/embeddings-biocap-openai-f32/biocap_text_embeddings.npz \
  --regional-species tmp/biocap-catalogs/nc-regional-v1/embeddings-biocap-openai-f32/species.jsonl \
  --fallback-embeddings tmp/biocap-validation/cloud-l4-animal-only/biocap_text_embeddings.npz \
  --fallback-species tmp/biocap-catalogs/fallback-taxonomy/image-field-animals-enriched.jsonl \
  --fallback-source birdnet-audio-labels \
  --require-fallback-hierarchy \
  --output-dir tmp/biocap-catalogs/nc-regional-birdnet-travel-v2
```

The hierarchy requirement intentionally rejects unresolved legacy names and
non-image BirdNET events instead of silently putting them into the image catalog.
The checked-in audit is
`catalogs/nc-regional-birdnet-travel-v2-report.json`.

Audit the conservative rank/uncertainty pilot against the frozen results:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/analyze_biocap_uncertainty.py \
  --benchmark-report tmp/biocap-validation/nc-v1-regional-birdnet-travel-v2/baseline_report.json \
  --species-list tmp/biocap-catalogs/nc-regional-birdnet-travel-v2/species.jsonl \
  --image-manifest tmp/biocap-datasets/nc-v1/benchmark_manifest.jsonl \
  --output tmp/biocap-validation/nc-v1-regional-birdnet-travel-v2/uncertainty_report.json
```

This reports exact-species precision/coverage, genus/family consensus outcomes,
and the effect of the positive-only NC prior. It does not claim calibrated
probability or open-set rejection; `nc-v1` has only 60 animal images, so a
larger independent set with non-animal cases is still required.

## Build a Candidate List

For real field-photo validation, the most practical path is a small local
iNaturalist sample. The prep script queries research-grade observations,
downloads licensed medium-size photos, keeps attribution metadata, and writes
everything under ignored `tmp/` paths.

```sh
uv run --python .venv-biocap/bin/python tools/biocap/prepare_inaturalist_photos.py \
  --accept-terms \
  --images-per-taxon 3
```

That produces:

- `tmp/biocap-datasets/inaturalist-field-photos/inat_species.jsonl`
- `tmp/biocap-datasets/inaturalist-field-photos/inat_image_manifest.jsonl`
- `tmp/biocap-datasets/inaturalist-field-photos/inat_attribution.jsonl`

Then run:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/validate_biocap.py \
  --species-list tmp/biocap-datasets/inaturalist-field-photos/inat_species.jsonl \
  --image-manifest tmp/biocap-datasets/inaturalist-field-photos/inat_image_manifest.jsonl \
  --output-dir tmp/biocap-validation/inaturalist-field-photos-001 \
  --trace-vision \
  --embedding-dtype float16
```

Use the resulting `rankings.csv` for top-1/top-5/top-10 review. Keep
`inat_attribution.jsonl` with the local images; do not commit or redistribute the
downloaded photos.

Semi-iNat 2021 is another good public validation source when its host is
reachable. Review the dataset terms first; the prep script requires
`--accept-terms`.

```sh
uv run --python .venv-biocap/bin/python tools/biocap/prepare_semi_inat.py \
  --accept-terms \
  --images-per-class 2 \
  --max-classes 100
```

That produces:

- `tmp/biocap-datasets/semi-inat-2021/semi_inat_species.jsonl`
- `tmp/biocap-datasets/semi-inat-2021/semi_inat_val_manifest.jsonl`

Then run:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/validate_biocap.py \
  --species-list tmp/biocap-datasets/semi-inat-2021/semi_inat_species.jsonl \
  --image-manifest tmp/biocap-datasets/semi-inat-2021/semi_inat_val_manifest.jsonl \
  --output-dir tmp/biocap-validation/semi-inat-001 \
  --trace-vision \
  --embedding-dtype float16
```

Omit `--images-per-class` and `--max-classes` for the full validation split.

For a fast smoke test, start with a small slice of the BirdNET labels:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/make_species_list.py \
  --limit 200 \
  --output tmp/biocap-validation/species_200.jsonl
```

For a realistic test, omit `--limit` and use the full Fieldnotes/BirdNET label
set. Later, replace or augment this with the curated regional multi-taxon list.

## Image Manifest

You can pass images directly with `--images`, or create a JSONL manifest:

```jsonl
{"path":"photos/red_shouldered_hawk.jpg","expectedScientificName":"Buteo lineatus"}
{"path":"photos/anna_hummingbird.jpg","expectedScientificName":"Calypte anna"}
```

Relative paths are resolved from the manifest directory.

## Run Parity Validation

```sh
uv run --python .venv-biocap/bin/python tools/biocap/validate_biocap.py \
  --species-list tmp/biocap-validation/species_200.jsonl \
  --image-manifest tmp/biocap-validation/images.jsonl \
  --output-dir tmp/biocap-validation/run-001 \
  --trace-vision
```

By default, the validator uses BioCAP's official zero-shot prompt ensemble:
the 80 OpenAI ImageNet templates imported by
`train_and_eval/evaluation/zero_shot_iid.py` from
`open_clip_train.imagenet_zeroshot_data.openai_imagenet_template`.

The class text inserted into those prompts defaults to `scientificName`, which
matches Fieldnotes' merge key. BioCAP's own benchmark runner also changes class
text by dataset: `taxon_com` for camera-trap/rare-species metadata and `asis`
for NABirds/Meta-Album labels. Use `--label-text-type taxon_common` when your
species list includes kingdom/phylum/class/order/family/genus/species/common
name fields and you want to mirror that benchmark mode.

Outputs:

- `biocap_text_embeddings.npz`: saved/reloaded text matrix plus species metadata.
- `biocap_vision_encoder_manual_traced.pt`: optional traced normalized vision tower.
- `rankings.csv`: top-1 comparison and expected-label ranks.
- `parity_report.json`: full top-k output and parity deltas.

The script exits non-zero if cached text rankings differ from full-model rankings
or if the isolated image encoder embedding diverges beyond tolerance.

## Optional Core ML Export Check

```sh
uv run --python .venv-biocap/bin/python tools/biocap/validate_biocap.py \
  --species-list tmp/biocap-validation/species_200.jsonl \
  --image-manifest tmp/biocap-validation/images.jsonl \
  --output-dir tmp/biocap-validation/coreml-run \
  --export-coreml tmp/biocap-validation/coreml-run/BioCAPVisionEncoder.mlpackage
```

This converts the normalized vision tower to Core ML and compares its output on a
zero tensor against PyTorch. By default it uses an export wrapper that reuses
BioCAP weights but expands ViT attention into primitive matmul/softmax ops with a
fixed single-image 224x224 shape. This avoids Core ML converter failures from
`torch.nn.MultiheadAttention` internals.

Use `--coreml-export-path openclip` only as a diagnostic when checking whether
coremltools can convert the raw traced OpenCLIP vision module directly.

After this passes, add real-image Core ML parity and device latency measurements
before app integration.

## Representative Phone-Like Validation

On 2026-06-30 we ran a larger validation pass to answer whether the test photos
look like plausible phone-camera field photos. The goal was not to create a final
benchmark, but to decide whether BioCAP is credible enough for an iOS integration
spike.

Build a broader iNaturalist sample:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/prepare_inaturalist_photos.py \
  --accept-terms \
  --images-per-taxon 4 \
  --output-dir tmp/biocap-datasets/inaturalist-phone-like-candidates
```

This produced 96 images across 24 taxa:

- birds: hummingbird, hawk, crow, cardinal, robin
- mammals: deer, squirrel, rabbit
- amphibians/reptiles: frogs, salamander, anole, turtle, snake
- insects: butterfly, bee, lady beetle, mantis
- plants/trees: dandelion, maple, clover
- fungi: turkey tail, fly agaric, oyster mushroom

Create contact sheets for visual QA:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/make_contact_sheets.py \
  --manifest tmp/biocap-datasets/inaturalist-phone-like-candidates/inat_image_manifest.jsonl \
  --output-dir tmp/biocap-validation/phone-like-contact-sheets
```

Visual inspection found that most images are representative of the target app
use case: close or zoomed field shots of a single organism, often with natural
background clutter. The set also includes useful hard cases: distant birds,
trail-camera-like frames, and two obvious screenshot artifacts for cardinal.
Those artifacts should not be treated as representative phone photos, but keeping
them in the conservative run is useful.

Run BioCAP with the official prompt ensemble and `float16` cached text embeddings:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/validate_biocap.py \
  --species-list tmp/biocap-datasets/inaturalist-phone-like-candidates/inat_species.jsonl \
  --image-manifest tmp/biocap-datasets/inaturalist-phone-like-candidates/inat_image_manifest.jsonl \
  --output-dir tmp/biocap-validation/inaturalist-phone-like-96-biocap-openai \
  --trace-vision \
  --embedding-dtype float16 \
  --device cpu
```

Result:

```json
{
  "coreMLDelta": null,
  "maxManualVisionDelta": 6.556510925292969e-07,
  "maxSimilarityDelta": 4.547834396362305e-05,
  "maxTracedDelta": 6.556510925292969e-07,
  "maxVisionDelta": 0.0,
  "passed": false,
  "topKMismatches": 1
}
```

The `float16` run had one strict top-k ordering mismatch on a near-tie, but the
top-1 prediction and expected-label rank did not change. The mismatch was on
`Amanita muscaria`; both full and cached rankings still had `Amanita muscaria`
as top-1.

Run the same validation with `float32` cached text embeddings:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/validate_biocap.py \
  --species-list tmp/biocap-datasets/inaturalist-phone-like-candidates/inat_species.jsonl \
  --image-manifest tmp/biocap-datasets/inaturalist-phone-like-candidates/inat_image_manifest.jsonl \
  --output-dir tmp/biocap-validation/inaturalist-phone-like-96-biocap-openai-float32 \
  --trace-vision \
  --embedding-dtype float32 \
  --device cpu
```

Result:

```json
{
  "coreMLDelta": null,
  "maxManualVisionDelta": 6.556510925292969e-07,
  "maxSimilarityDelta": 0.0,
  "maxTracedDelta": 6.556510925292969e-07,
  "maxVisionDelta": 0.0,
  "passed": true,
  "topKMismatches": 0
}
```

Closed-set ranking on the 96-image set:

```text
top1: 95/96 = 0.990
top3: 96/96 = 1.000
top5: 96/96 = 1.000
top10: 96/96 = 1.000
```

The only top-1 miss was one of the obvious cardinal screenshot artifacts:

```text
expected: Cardinalis cardinalis
top1:     Turdus migratorius
rank:     2
```

Excluding the two cardinal screenshot artifacts:

```text
top1: 94/94 = 1.000
top3: 94/94 = 1.000
top5: 94/94 = 1.000
top10: 94/94 = 1.000
```

Interpretation:

- This is strong enough to proceed to an iOS integration spike.
- Use `float32` label embeddings first for exact parity and simpler debugging.
- Re-test `float16` later if bundle size matters; the observed drift was small
  and did not affect top-1 on this run.
- This is still a closed-set sanity check, not final product accuracy. The next
  accuracy test should use a larger candidate list with visually similar species.

## Audio-Overlap Candidate Validation

For the first app spike, we moved from the 24-class closed-set test to the full
Fieldnotes/BirdNET candidate list. This is useful for validating mechanics and
the photo/audio merge key, but it is **not** the final image candidate list.
BirdNET is an audio label set and does not contain many visually identifiable
taxa, including beetles and many other invertebrates.

Build the audio-overlap species list from the checked-in BirdNET labels:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/make_species_list.py \
  --output tmp/biocap-validation/birdnet-6522-species.jsonl
```

Filter the phone-like iNaturalist manifest to labels present in that list:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/filter_image_manifest.py \
  --species-list tmp/biocap-validation/birdnet-6522-species.jsonl \
  --image-manifest tmp/biocap-datasets/inaturalist-phone-like-candidates/inat_image_manifest.jsonl \
  --output tmp/biocap-validation/birdnet-6522-phone-like-birds.jsonl \
  --write-missing tmp/biocap-validation/birdnet-6522-phone-like-excluded.jsonl
```

Result:

```json
{
  "excludedImages": 60,
  "inputImages": 96,
  "keptImages": 36,
  "speciesCount": 6522
}
```

Run the closed-set BirdNET-overlap validation:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/validate_biocap.py \
  --species-list tmp/biocap-validation/birdnet-6522-species.jsonl \
  --image-manifest tmp/biocap-validation/birdnet-6522-phone-like-birds.jsonl \
  --output-dir tmp/biocap-validation/birdnet-6522-phone-like-36-biocap-openai-float32 \
  --embedding-dtype float32 \
  --device auto \
  --top-k 10 \
  --batch-size 256 \
  --species-batch-size 128
```

Parity result:

```json
{
  "coreMLDelta": null,
  "maxManualVisionDelta": 0.0,
  "maxSimilarityDelta": 0.0,
  "maxTracedDelta": null,
  "maxVisionDelta": 0.0,
  "passed": true,
  "topKMismatches": 0
}
```

Open-set ranking on the 36 overlapping phone-like images:

```text
top1:  26/36 = 0.722
top3:  31/36 = 0.861
top5:  31/36 = 0.861
top10: 32/36 = 0.889
```

The misses are useful hard cases rather than evidence that the integration path
is broken. Examples include raptors competing with other raptors, crows competing
with other corvids, and a bullfrog image where the expected label landed at rank
13. This is a more honest mechanics test than the 24-class run, but it should be
read as audio-overlap validation only.

## Image-Native Candidate Lists

The image model should classify against an image-native candidate list. It does
not need to be restricted to species that BirdNET can hear. When an image label
and an audio label share the same `scientificName`, the app can merge those
sources into one Atlas species entry. When there is no audio equivalent, the
photo prediction should still be shown as an image-only result.

Build a beetle-inclusive smoke list from BioCAP's wiki-species export plus the
BirdNET overlap labels:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/make_image_species_list.py \
  --order Coleoptera \
  --include-birdnet \
  --output tmp/biocap-validation/image-coleoptera-plus-birdnet-species.jsonl
```

That list includes BioCAP taxonomy rows for beetles, including Lucanidae/stag
beetle genera, while still preserving BirdNET rows for audio/photo overlap.
The generated JSONL records include `scientificName`, `commonName`, `taxon`,
taxonomic context such as `class`, `order`, and `family`, and a `sources` array
that records whether the row came from BioCAP wiki species, BirdNET labels, or
both.

On the local BioCAP taxonomy export, the Coleoptera + BirdNET command produced
41,700 rows: 35,178 beetle rows plus the 6,522 BirdNET overlap rows.

For the first app pass, leave out plants and fungi. The local BioCAP taxonomy
export has 107,026 global plant rows and 12,915 fungi rows, so excluding them
keeps the first image-native matrix smaller and reduces irrelevant lookalike
competition. Add plants/trees later as a separate candidate-list expansion.
The animal-only smoke list below produced 72,574 rows on the local taxonomy
export.

Other useful scoped lists:

```sh
# Stag beetle family only, useful for very fast debugging.
uv run --python .venv-biocap/bin/python tools/biocap/make_image_species_list.py \
  --family Lucanidae \
  --include-birdnet \
  --output tmp/biocap-validation/image-lucanidae-plus-birdnet-species.jsonl

# Broader phone-photo animal smoke list. This omits plants and fungi.
uv run --python .venv-biocap/bin/python tools/biocap/make_image_species_list.py \
  --class-name Aves \
  --class-name Mammalia \
  --class-name Amphibia \
  --class-name Reptilia \
  --order Coleoptera \
  --order Odonata \
  --order Orthoptera \
  --exclude-kingdom Plantae \
  --exclude-kingdom Fungi \
  --include-birdnet \
  --output tmp/biocap-validation/image-field-animals-no-plants-fungi-species.jsonl
```

Use the generated image-native JSONL anywhere `validate_biocap.py` or
`export_ios_assets.py` accepts `--species-list`. For example, the next app asset
export should point at an image-native file instead of
`birdnet-6522-species.jsonl`.

Run BioCAP validation against that image-native candidate list before exporting:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/validate_biocap.py \
  --species-list tmp/biocap-validation/image-coleoptera-plus-birdnet-species.jsonl \
  --images /path/to/field-photo.jpg \
  --output-dir tmp/biocap-validation/image-coleoptera-plus-birdnet-biocap-openai-float32 \
  --embedding-dtype float32 \
  --device auto \
  --top-k 10 \
  --batch-size 256 \
  --species-batch-size 128
```

The official BioCAP prompt ensemble is much slower than the single-prompt
mechanics check because every species is embedded across many prompt templates.
On 2026-06-30, an interactive Coleoptera + BirdNET run on Apple `mps` was
stopped after 768/41,700 species because it was on track to take hours. For
quick iteration, use the smaller Lucanidae smoke list or run the broad export as
a long cached job.

### L4 Cloud Embedding Job

Use SkyPilot for the full animal-only text embedding run. The L4 config follows
the newer GCP/autostop pattern from `~/proj/safety-reasoners` and
`~/proj/colfastvlm`, mounts the local BioCAP wiki-species CSVs, builds the
animal-only species list, and writes resumable text-embedding shards:

```sh
sky launch -c fieldnotes-biocap-l4 tools/biocap/skypilot/l4-embed-text.yaml
```

For a real run, mount a GCS bucket in
`tools/biocap/skypilot/l4-embed-text.yaml` and point `BIOCAP_OUTPUT_DIR` at that
mount so spot-preempted work and completed artifacts survive VM teardown:

```sh
sky launch -c fieldnotes-biocap-l4 tools/biocap/skypilot/l4-embed-text.yaml \
  --env BIOCAP_OUTPUT_DIR=/gcs/fieldnotes-biocap/image-field-animals-no-plants-fungi-l4-float32
```

The embedding job writes:

- `biocap_text_embeddings.npz`: final averaged/normalized text matrix.
- `embedding_report.json`: model, prompt, dtype, count, device, and shard summary.
- `text_embedding_shards/*.npz`: resumable per-batch shards.
- a copy of the generated species JSONL used for the matrix.

The output from `embed_biocap_text.py` can be passed directly to
`export_ios_assets.py` as `--embeddings`.

Cloud run completed on 2026-07-01. The final report:

```json
{
  "batchSize": 512,
  "device": "cuda",
  "embeddingDim": 512,
  "embeddingDtype": "float32",
  "labelTextType": "scientific",
  "model": "hf-hub:imageomics/biocap",
  "promptPreset": "biocap-openai",
  "promptTemplateCount": 81,
  "shardCount": 142,
  "speciesBatchSize": 512,
  "speciesCount": 72574
}
```

Pull the completed artifacts:

```sh
mkdir -p tmp/biocap-validation/cloud-l4-animal-only
gcloud storage cat \
  gs://fieldnotes-biocap/image-field-animals-no-plants-fungi-l4-float32/biocap_text_embeddings.npz \
  > tmp/biocap-validation/cloud-l4-animal-only/biocap_text_embeddings.npz
gcloud storage cat \
  gs://fieldnotes-biocap/image-field-animals-no-plants-fungi-l4-float32/image-field-animals-no-plants-fungi-species.jsonl \
  > tmp/biocap-validation/cloud-l4-animal-only/image-field-animals-no-plants-fungi-species.jsonl
gcloud storage cat \
  gs://fieldnotes-biocap/image-field-animals-no-plants-fungi-l4-float32/embedding_report.json \
  > tmp/biocap-validation/cloud-l4-animal-only/embedding_report.json
```

Export the animal-only matrix into local iOS resources:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/export_ios_assets.py \
  --embeddings tmp/biocap-validation/cloud-l4-animal-only/biocap_text_embeddings.npz \
  --species-list tmp/biocap-validation/cloud-l4-animal-only/image-field-animals-no-plants-fungi-species.jsonl \
  --model tmp/biocap-validation/coreml-smoke-run-static-manual/BioCAPVisionEncoder.mlpackage
```

That produced:

```text
BioCAPTextEmbeddings.f32   142 MB
BioCAPSpecies.json         9.6 MB
speciesCount               72,574
```

Enrich common names before exporting if the species list came from BioCAP wiki
species. BirdNET overlap rows already have common names, but most wiki rows use
the scientific name as a placeholder. The enrichment step preserves row order, so
it can be used with the existing embedding matrix:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/fetch_inaturalist_common_names.py \
  --species-list tmp/biocap-validation/cloud-l4-animal-only/image-field-animals-no-plants-fungi-species.jsonl \
  --output tmp/biocap-validation/cloud-l4-animal-only/inaturalist-common-names.jsonl \
  --cache-dir tmp/biocap-validation/inaturalist-taxa-cache

uv run --python .venv-biocap/bin/python tools/biocap/fetch_gbif_common_names.py \
  --species-list tmp/biocap-validation/cloud-l4-animal-only/image-field-animals-no-plants-fungi-species.jsonl \
  --output tmp/biocap-validation/cloud-l4-animal-only/gbif-common-names-no-coleoptera.jsonl \
  --cache-dir tmp/biocap-validation/gbif-species-cache \
  --taxon-key Aves=212 \
  --taxon-key Mammalia=359 \
  --taxon-key Amphibia=131 \
  --taxon-key Squamata=11592253 \
  --taxon-key Testudines=11418114 \
  --taxon-key Crocodylia=11493978 \
  --taxon-key Sphenodontia=11569602 \
  --taxon-key Odonata=789 \
  --taxon-key Orthoptera=1458

uv run --python .venv-biocap/bin/python tools/biocap/enrich_common_names.py \
  --species-list tmp/biocap-validation/cloud-l4-animal-only/image-field-animals-no-plants-fungi-species.jsonl \
  --vernacular-jsonl tmp/biocap-validation/cloud-l4-animal-only/inaturalist-common-names.jsonl \
  --vernacular-jsonl tmp/biocap-validation/cloud-l4-animal-only/gbif-common-names-no-coleoptera.jsonl \
  --output tmp/biocap-validation/cloud-l4-animal-only/image-field-animals-no-plants-fungi-species.inat-gbif-enriched.jsonl
```

The current offline enrichment sources are:

- `tmp/biocap-validation/cloud-l4-animal-only/inaturalist-common-names.jsonl`
  for iNaturalist preferred English names.
- `tmp/biocap-validation/cloud-l4-animal-only/gbif-common-names-no-coleoptera.jsonl`
  for scoped GBIF English vernacular names.
- `Fieldnotes/Fieldnotes/Resources/Labels/labels_en.json` for BirdNET overlap.
- optional extra `--vernacular-jsonl` / `--vernacular-csv` inputs for future
  source exports.

The iNaturalist pull on 2026-07-01 paged the current animal-only groups
(`Aves`, `Mammalia`, `Amphibia`, `Reptilia`, `Coleoptera`, `Odonata`,
`Orthoptera`) with `id_above` sliding windows and matched 29,323 exact
scientific names from the 72,574-species candidate list. After combining
iNaturalist and BirdNET overlap names, enrichment produced:

```json
{
  "exact": 23240,
  "fallback": 41878,
  "kept": 6509,
  "parent": 947
}
```

A scoped GBIF supplement was then run for vertebrates plus `Odonata` and
`Orthoptera`. Full `Coleoptera` was intentionally not crawled in this pass:
GBIF had 373,306 accepted beetle species records under `Coleoptera`, and the
species search payload includes large description fields. The scoped GBIF run
matched 27,206 exact scientific names and added 1,973 net display names after
merging with iNaturalist and BirdNET. The combined source-derived enrichment
produced:

```json
{
  "exact": 25127,
  "fallback": 39905,
  "kept": 6509,
  "parent": 1033
}
```

Combined source-derived common-name coverage is 32,649 / 72,574 species
(`44.99%`). The remaining 39,925 rows fall back to scientific names.

Many global insect species still do not have a stable English common name in
these sources. Those rows intentionally fall back to the scientific name rather
than inventing a label.

If an exact common name is missing, the script falls back from an infraspecies to
the parent binomial when available. For example:

```text
Sylvilagus floridanus nigronuchalis -> Eastern Cottontail
```

After enrichment, export using the enriched JSONL:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/export_ios_assets.py \
  --embeddings tmp/biocap-validation/cloud-l4-animal-only/biocap_text_embeddings.npz \
  --species-list tmp/biocap-validation/cloud-l4-animal-only/image-field-animals-no-plants-fungi-species.inat-gbif-enriched.jsonl \
  --model tmp/biocap-validation/coreml-smoke-run-static-manual/BioCAPVisionEncoder.mlpackage
```

Retest a photo against cached embeddings without recomputing text:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/classify_biocap_cached.py \
  --embeddings tmp/biocap-validation/cloud-l4-animal-only/biocap_text_embeddings.npz \
  --species-list tmp/biocap-validation/cloud-l4-animal-only/image-field-animals-no-plants-fungi-species.jsonl \
  --images tmp/biocap-validation/user-beetle-screenshot-crop.jpg \
  --output tmp/biocap-validation/cloud-l4-animal-only/user-beetle-cached-rankings.csv \
  --top-k 10 \
  --device auto
```

The beetle screenshot crop ranked as stag beetles with the full animal-only
matrix:

```text
1. Lucanus marazziorum                   0.383
2. Lucanus parryi                        0.377
3. Lucanus fortunei                      0.376
4. Lucanus swinhoei                      0.373
5. Cyclommatus lunifer                   0.368
```

The iOS fixture test passed against the exported 72,574-species resources:

```sh
xcodebuild test \
  -workspace Fieldnotes.xcworkspace \
  -scheme Fieldnotes \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  -only-testing:FieldnotesTests/FieldnotesTests/testBioCAPFixtureRanksExpectedSpeciesWhenLocalAssetsExist
```

Result: passed. The fixture ranked the expected species first in 6.281 seconds.

### Beetle Screenshot Sanity Check

The user-provided beetle example was a screenshot of the app UI, not the raw
camera image, so a clean accuracy claim would be overstated. For a directional
check, the visible photo area was cropped to:

```text
tmp/biocap-validation/user-beetle-screenshot-crop.jpg
```

Build a Lucanidae-only candidate list:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/make_image_species_list.py \
  --family Lucanidae \
  --output tmp/biocap-validation/image-lucanidae-only-species.jsonl
```

Run the official BioCAP prompt path:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/validate_biocap.py \
  --species-list tmp/biocap-validation/image-lucanidae-only-species.jsonl \
  --images tmp/biocap-validation/user-beetle-screenshot-crop.jpg \
  --output-dir tmp/biocap-validation/image-lucanidae-user-beetle-biocap-openai-float32 \
  --embedding-dtype float32 \
  --device auto \
  --top-k 10 \
  --batch-size 256 \
  --species-batch-size 256
```

Result:

```json
{
  "passed": true,
  "topKMismatches": 0,
  "maxSimilarityDelta": 0.0,
  "maxVisionDelta": 0.0,
  "maxManualVisionDelta": 0.0
}
```

Top candidates:

```text
1. Lucanus marazziorum      0.383
2. Lucanus parryi           0.377
3. Lucanus fortunei         0.376
4. Lucanus swinhoei         0.373
5. Cyclommatus lunifer      0.368
```

This confirms the prior bird/cricket result was primarily a candidate-list
problem: the app was scoring the beetle photo against BirdNET/audio labels, not
against image-native beetle labels.

## iOS Spike Assets

Use a validated image-native float32 output to generate local app resources for
the iOS spike:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/export_ios_assets.py \
  --embeddings tmp/biocap-validation/image-coleoptera-plus-birdnet-biocap-openai-float32/biocap_text_embeddings.npz \
  --species-list tmp/biocap-validation/image-coleoptera-plus-birdnet-species.jsonl \
  --model tmp/biocap-validation/coreml-smoke-run-static-manual/BioCAPVisionEncoder.mlpackage
```

Pass `--image-manifest`, `--rankings`, and `--fixture-scientific-name` only when
those files were produced from the same image-native candidate list.

That writes generated resources under
`Fieldnotes/Fieldnotes/Resources/BioCAP/`:

- `BioCAPTextEmbeddings.f32`: row-major float32 text embedding matrix.
- `BioCAPSpecies.json`: scientific-name keyed species metadata.
- `BioCAPConfig.json`: embedding shape and prompt/export metadata.
- `Models/BioCAPVisionEncoder.mlpackage`: normalized image encoder.
- `TestFixtures/BioCAPFixture.jpg` and `.json`: one top-1 fixture for XCTest.

The generated directory is ignored by Git because the model package is about
165 MB and should be regenerated from validation artifacts. In this full-list
spike, the raw float32 text matrix is about 13 MB and the generated BioCAP
resource directory is about 178 MB.

The iOS spike currently consists of:

- `BioCAPImageClassifier`, which loads Xcode's compiled `.mlmodelc` or a local
  `.mlpackage`, preprocesses a `UIImage` to BioCAP/OpenCLIP's 224x224 tensor,
  decodes float16/float32 model output, normalizes it, and ranks against cached
  text embeddings.
- `testBioCAPFixtureRanksExpectedSpeciesWhenLocalAssetsExist`, which skips when
  local BioCAP assets are absent and runs a real Core ML fixture classification
  when they are present.

Validation run on 2026-06-30:

```sh
xcodebuild test \
  -workspace Fieldnotes.xcworkspace \
  -scheme Fieldnotes \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  -only-testing:FieldnotesTests/FieldnotesTests/testBioCAPFixtureRanksExpectedSpeciesWhenLocalAssetsExist
```

Result: passed. The app bundle contained Xcode's compiled
`BioCAPVisionEncoder.mlmodelc`, float32 cached text embeddings, and the
`Calypte anna` fixture; the fixture ranked the expected scientific name first.
The simulator path uses CPU-only Core ML execution because `.all` returned a
zero image embedding for this converted model on the tested simulator runtime.

## Smoke Result In This Checkout

Using a local AvianVisitors illustration as a mechanics-only test image, the
harness produced:

```json
{
  "coreMLDelta": 0.002319931983947754,
  "maxManualVisionDelta": 2.0116567611694336e-07,
  "maxSimilarityDelta": 0.0,
  "maxTracedDelta": 2.0116567611694336e-07,
  "maxVisionDelta": 0.0,
  "passed": true,
  "topKMismatches": 0
}
```

That proves the cached text matrix and isolated image encoder path can match the
full BioCAP/OpenCLIP path. It does not prove field-photo accuracy, because the
sample image is an illustration.

## Prompt Options

The default is now `--prompt-preset biocap-openai`, matching BioCAP's zero-shot
evaluation prompt ensemble. Use `--prompt-preset simple` only for quick
mechanics debugging:

```text
a photo of {scientific_name}
```

You can also override prompts explicitly:

```sh
--prompt-template 'a field photo of {label_text}.'
```

Multiple custom `--prompt-template` values are averaged per species, with each
prompt embedding normalized before averaging and the final row normalized again.
