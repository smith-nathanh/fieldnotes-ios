#!/usr/bin/env python3
"""Precompute BioCAP text embeddings without requiring validation images.

This is the cloud/offline companion to validate_biocap.py. It renders the same
species prompts, encodes them with BioCAP's text tower, averages prompt
embeddings into one row per species, and writes the cached matrix expected by
export_ios_assets.py. Shards are written first so spot GPU jobs can resume.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

import numpy as np

from validate_biocap import (
    BIOCAP_OPENAI_TEMPLATES,
    MODEL_NAME,
    PARITY_PROMPT,
    choose_device,
    encode_text_matrix,
    load_species,
)

try:
    import open_clip
except ImportError as exc:  # pragma: no cover - exercised by cloud setup
    raise SystemExit(
        "Missing dependency open_clip_torch. Install with:\n"
        "  uv pip install -r tools/biocap/requirements.txt"
    ) from exc


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--species-list",
        type=Path,
        required=True,
        help="JSONL/JSON/CSV species list with scientificName, commonName, taxon.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        required=True,
        help="Directory for text shards and biocap_text_embeddings.npz.",
    )
    parser.add_argument(
        "--prompt-template",
        action="append",
        default=None,
        help=(
            "Custom prompt template. May be repeated. Fields match "
            "validate_biocap.py. Overrides --prompt-preset."
        ),
    )
    parser.add_argument(
        "--prompt-preset",
        choices=["biocap-openai", "simple"],
        default="biocap-openai",
        help="Prompt template set. biocap-openai matches BioCAP zero-shot evaluation.",
    )
    parser.add_argument(
        "--label-text-type",
        choices=["scientific", "common", "scientific_common", "taxon", "taxon_common"],
        default="scientific",
        help="Class text inserted into prompt templates.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=512,
        help="Text prompt embedding batch size.",
    )
    parser.add_argument(
        "--species-batch-size",
        type=int,
        default=512,
        help="Number of species per resumable shard.",
    )
    parser.add_argument(
        "--device",
        choices=["auto", "cpu", "mps", "cuda"],
        default="auto",
        help="Torch device.",
    )
    parser.add_argument(
        "--embedding-dtype",
        choices=["float32", "float16"],
        default="float32",
        help="Saved text embedding dtype.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Recompute existing shard files.",
    )
    return parser.parse_args()


def prompt_config(args: argparse.Namespace) -> tuple[list[str], str]:
    if args.prompt_template:
        return args.prompt_template, "custom"
    if args.prompt_preset == "simple":
        return [PARITY_PROMPT], "simple"
    return BIOCAP_OPENAI_TEMPLATES, "biocap-openai"


def shard_path(shard_dir: Path, start: int, end: int) -> Path:
    return shard_dir / f"text_embeddings_{start:06d}_{end:06d}.npz"


def valid_shard(path: Path, expected_rows: int) -> bool:
    if not path.exists():
        return False
    try:
        data = np.load(path)
        embeddings = data["embeddings"]
    except Exception:
        return False
    return embeddings.shape == (expected_rows, 512)


def write_report(path: Path, report: dict[str, object]) -> None:
    path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")


def main() -> None:
    args = parse_args()
    output_dir = args.output_dir
    shard_dir = output_dir / "text_embedding_shards"
    output_dir.mkdir(parents=True, exist_ok=True)
    shard_dir.mkdir(parents=True, exist_ok=True)

    templates, prompt_preset = prompt_config(args)
    species = load_species(args.species_list)
    device = choose_device(args.device)

    print(f"loading {MODEL_NAME} on {device}", file=sys.stderr)
    model, _, _ = open_clip.create_model_and_transforms(MODEL_NAME)
    tokenizer = open_clip.get_tokenizer(MODEL_NAME)
    model.to(device)
    model.eval()

    shard_files: list[Path] = []
    for start in range(0, len(species), args.species_batch_size):
        end = min(start + args.species_batch_size, len(species))
        path = shard_path(shard_dir, start, end)
        expected_rows = end - start
        if not args.force and valid_shard(path, expected_rows):
            print(f"reusing text embeddings shard {start}/{len(species)}", file=sys.stderr)
            shard_files.append(path)
            continue

        matrix = encode_text_matrix(
            model=model,
            tokenizer=tokenizer,
            species=species[start:end],
            templates=templates,
            label_text_type=args.label_text_type,
            batch_size=args.batch_size,
            species_batch_size=expected_rows,
            device=device,
        )
        np.savez_compressed(
            path,
            embeddings=matrix.astype(args.embedding_dtype),
            start=np.asarray([start]),
            end=np.asarray([end]),
        )
        print(f"wrote text embeddings shard {path}", file=sys.stderr)
        shard_files.append(path)

    matrices = [np.load(path)["embeddings"].astype(np.float32) for path in shard_files]
    embeddings = np.concatenate(matrices, axis=0)
    norms = np.linalg.norm(embeddings, axis=1, keepdims=True)
    embeddings = embeddings / norms
    saved_embeddings = embeddings.astype(args.embedding_dtype)

    embeddings_path = output_dir / "biocap_text_embeddings.npz"
    np.savez_compressed(
        embeddings_path,
        embeddings=saved_embeddings,
        scientific_names=np.asarray([item.scientific_name for item in species]),
        common_names=np.asarray([item.common_name for item in species]),
        taxa=np.asarray([item.taxon for item in species]),
        prompt_templates=np.asarray(templates),
        label_text_type=np.asarray([args.label_text_type]),
        prompt_preset=np.asarray([prompt_preset]),
        model_name=np.asarray([MODEL_NAME]),
    )
    shutil.copy2(args.species_list, output_dir / args.species_list.name)

    report = {
        "model": MODEL_NAME,
        "embeddingPath": str(embeddings_path),
        "speciesList": str(args.species_list),
        "speciesCount": len(species),
        "embeddingDim": int(saved_embeddings.shape[1]),
        "embeddingDtype": args.embedding_dtype,
        "promptPreset": prompt_preset,
        "promptTemplateCount": len(templates),
        "labelTextType": args.label_text_type,
        "batchSize": args.batch_size,
        "speciesBatchSize": args.species_batch_size,
        "device": str(device),
        "shardCount": len(shard_files),
    }
    write_report(output_dir / "embedding_report.json", report)
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
