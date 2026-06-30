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
- plants/fungi: dandelion, maple, clover, turkey tail, fly agaric, oyster mushroom

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

## Full Candidate Validation

For the app spike, we moved from the 24-class closed-set test to the full
Fieldnotes/BirdNET candidate list so the ranking includes realistic visually
similar competitors.

Build the full species list from the checked-in BirdNET labels:

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

Run the open-set validation:

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
13. This is a more honest test than the 24-class run because it exercises the
same scientific-name candidate space that can be shared with the audio pipeline.

## iOS Spike Assets

Use the full-list float32 validation output to generate local app resources for
the iOS spike:

```sh
uv run --python .venv-biocap/bin/python tools/biocap/export_ios_assets.py \
  --embeddings tmp/biocap-validation/birdnet-6522-phone-like-36-biocap-openai-float32/biocap_text_embeddings.npz \
  --species-list tmp/biocap-validation/birdnet-6522-species.jsonl \
  --model tmp/biocap-validation/coreml-smoke-run-static-manual/BioCAPVisionEncoder.mlpackage \
  --image-manifest tmp/biocap-validation/birdnet-6522-phone-like-birds.jsonl \
  --rankings tmp/biocap-validation/birdnet-6522-phone-like-36-biocap-openai-float32/rankings.csv \
  --fixture-scientific-name 'Calypte anna'
```

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
