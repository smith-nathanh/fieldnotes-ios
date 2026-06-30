# BioCAP Phase 0 Validation

This directory is only for workstation validation. It does not wire BioCAP into the
iOS app.

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
