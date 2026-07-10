#!/usr/bin/env python3
"""Merge a regional BioCAP matrix with selected rows from a fallback matrix."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


CONFIG_KEYS = (
    "model_name",
    "prompt_templates",
    "label_text_type",
    "prompt_preset",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--regional-embeddings", type=Path, required=True)
    parser.add_argument("--regional-species", type=Path, required=True)
    parser.add_argument("--fallback-embeddings", type=Path, required=True)
    parser.add_argument("--fallback-species", type=Path, required=True)
    parser.add_argument(
        "--fallback-source",
        default="birdnet-audio-labels",
        help="Only fallback rows whose sources list contains this value.",
    )
    parser.add_argument(
        "--require-fallback-hierarchy",
        action="store_true",
        help="Exclude selected fallback rows that still lack a kingdom.",
    )
    parser.add_argument("--output-dir", type=Path, required=True)
    return parser.parse_args()


def read_jsonl(path: Path) -> list[dict[str, object]]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def normalized_sources(row: dict[str, object]) -> list[object]:
    sources = row.get("sources") or []
    return list(sources) if isinstance(sources, list) else [sources]


def has_source(row: dict[str, object], source: str) -> bool:
    return source in normalized_sources(row)


def load_matrix(
    path: Path, rows: list[dict[str, object]]
) -> tuple[np.ndarray, dict[str, np.ndarray]]:
    with np.load(path) as archive:
        missing = [key for key in ("embeddings", "scientific_names", *CONFIG_KEYS) if key not in archive.files]
        if missing:
            raise SystemExit(f"Embedding archive {path} is missing keys: {missing}")
        names = [str(value) for value in archive["scientific_names"].tolist()]
        expected = [str(row.get("scientificName") or "") for row in rows]
        if names != expected:
            raise SystemExit(f"Embedding/species order mismatch for {path}")
        matrix = archive["embeddings"].astype(np.float32)
        config = {key: np.array(archive[key]) for key in CONFIG_KEYS}
    if matrix.shape != (len(rows), 512):
        raise SystemExit(f"Unexpected embedding shape {matrix.shape} for {path}")
    if not np.isfinite(matrix).all():
        raise SystemExit(f"Non-finite embedding value in {path}")
    norms = np.linalg.norm(matrix, axis=1)
    if np.any(norms <= 0):
        raise SystemExit(f"Zero-norm embedding row in {path}")
    return matrix / norms[:, None], config


def validate_matching_config(
    regional: dict[str, np.ndarray], fallback: dict[str, np.ndarray]
) -> None:
    for key in CONFIG_KEYS:
        if not np.array_equal(regional[key], fallback[key]):
            raise SystemExit(f"Embedding configuration mismatch for {key}")


def merge_catalogs(
    regional_rows: list[dict[str, object]],
    regional_matrix: np.ndarray,
    fallback_rows: list[dict[str, object]],
    fallback_matrix: np.ndarray,
    fallback_source: str,
    require_fallback_hierarchy: bool = False,
) -> tuple[list[dict[str, object]], np.ndarray, dict[str, int]]:
    regional_by_name = {
        str(row["scientificName"]): (row, regional_matrix[index])
        for index, row in enumerate(regional_rows)
    }
    fallback_by_name = {
        str(row["scientificName"]): (row, fallback_matrix[index])
        for index, row in enumerate(fallback_rows)
        if has_source(row, fallback_source)
        and (not require_fallback_hierarchy or bool(row.get("kingdom")))
    }
    names = sorted(regional_by_name.keys() | fallback_by_name.keys())
    output_rows: list[dict[str, object]] = []
    output_vectors: list[np.ndarray] = []
    for name in names:
        if name in regional_by_name:
            row, vector = regional_by_name[name]
            output = dict(row)
            output["catalogTier"] = "regional"
            if name in fallback_by_name:
                output["alsoInTravelFallback"] = True
                output["fallbackSources"] = normalized_sources(fallback_by_name[name][0])
        else:
            row, vector = fallback_by_name[name]
            output = dict(row)
            output["catalogTier"] = "travelFallback"
        output_rows.append(output)
        output_vectors.append(vector)
    matrix = np.stack(output_vectors).astype(np.float32)
    report = {
        "regionalRows": len(regional_by_name),
        "selectedFallbackRows": len(fallback_by_name),
        "overlapRows": len(regional_by_name.keys() & fallback_by_name.keys()),
        "fallbackOnlyRows": len(fallback_by_name.keys() - regional_by_name.keys()),
        "mergedRows": len(output_rows),
    }
    return output_rows, matrix, report


def write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text(
        "\n".join(json.dumps(row, sort_keys=True) for row in rows) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    args = parse_args()
    regional_rows = read_jsonl(args.regional_species)
    fallback_rows = read_jsonl(args.fallback_species)
    regional_matrix, regional_config = load_matrix(args.regional_embeddings, regional_rows)
    fallback_matrix, fallback_config = load_matrix(args.fallback_embeddings, fallback_rows)
    validate_matching_config(regional_config, fallback_config)
    rows, matrix, report = merge_catalogs(
        regional_rows,
        regional_matrix,
        fallback_rows,
        fallback_matrix,
        args.fallback_source,
        args.require_fallback_hierarchy,
    )
    args.output_dir.mkdir(parents=True, exist_ok=True)
    species_path = args.output_dir / "species.jsonl"
    embeddings_path = args.output_dir / "biocap_text_embeddings.npz"
    write_jsonl(species_path, rows)
    np.savez_compressed(
        embeddings_path,
        embeddings=matrix,
        scientific_names=np.asarray([row["scientificName"] for row in rows]),
        common_names=np.asarray([row.get("commonName") or row["scientificName"] for row in rows]),
        taxa=np.asarray([row.get("taxon") or "unknown" for row in rows]),
        **regional_config,
    )
    report.update(
        {
            "fallbackSource": args.fallback_source,
            "embeddingShape": list(matrix.shape),
            "embeddingDtype": str(matrix.dtype),
            "embeddingArchive": str(embeddings_path),
            "speciesList": str(species_path),
        }
    )
    (args.output_dir / "merge_report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
