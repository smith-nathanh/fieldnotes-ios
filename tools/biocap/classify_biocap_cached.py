#!/usr/bin/env python3
"""Classify images with BioCAP vision encoder and cached text embeddings."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import numpy as np

from validate_biocap import MODEL_NAME, choose_device, encode_image, load_species, topk

try:
    import open_clip
except ImportError as exc:  # pragma: no cover - exercised by local env setup
    raise SystemExit(
        "Missing dependency open_clip_torch. Install with:\n"
        "  uv pip install -r tools/biocap/requirements.txt"
    ) from exc


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--embeddings",
        type=Path,
        required=True,
        help="BioCAP text embeddings .npz from embed_biocap_text.py or validate_biocap.py.",
    )
    parser.add_argument(
        "--species-list",
        type=Path,
        required=True,
        help="JSONL/JSON/CSV species list matching the embedding row order.",
    )
    parser.add_argument("--images", nargs="+", type=Path, required=True)
    parser.add_argument("--output", type=Path, help="Optional rankings CSV path.")
    parser.add_argument("--top-k", type=int, default=10)
    parser.add_argument(
        "--device",
        choices=["auto", "cpu", "mps", "cuda"],
        default="auto",
        help="Torch device.",
    )
    return parser.parse_args()


def load_text_matrix(path: Path, expected_rows: int) -> np.ndarray:
    data = np.load(path)
    embeddings = data["embeddings"].astype(np.float32)
    if embeddings.shape != (expected_rows, 512):
        raise SystemExit(
            f"Embedding matrix shape {embeddings.shape} does not match "
            f"{expected_rows} species rows."
        )
    embeddings /= np.linalg.norm(embeddings, axis=1, keepdims=True)
    return embeddings


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    args = parse_args()
    species = load_species(args.species_list)
    text_matrix = load_text_matrix(args.embeddings, len(species))

    device = choose_device(args.device)
    print(f"loading {MODEL_NAME} on {device}")
    model, _, preprocess = open_clip.create_model_and_transforms(MODEL_NAME)
    model.to(device)
    model.eval()

    rows: list[dict[str, object]] = []
    for image_path in args.images:
        image_embedding = encode_image(model, preprocess, image_path, device).numpy()
        scores = text_matrix @ image_embedding
        predictions = topk(scores, species, args.top_k)
        print(json.dumps({"image": str(image_path), "topK": predictions}, indent=2))
        for prediction in predictions:
            rows.append({"image": str(image_path), **prediction})

    if args.output and rows:
        write_csv(args.output, rows)


if __name__ == "__main__":
    main()
