#!/usr/bin/env python3
"""Benchmark BioCAP images against a cached text-embedding catalog."""

from __future__ import annotations

import argparse
import csv
import json
import platform
import resource
import time
from collections import defaultdict
from pathlib import Path
from typing import Iterable

import numpy as np

from validate_biocap import MODEL_NAME, Species, choose_device, encode_image, load_species, topk

try:
    import open_clip
except ImportError as exc:  # pragma: no cover - exercised by local env setup
    raise SystemExit(
        "Missing dependency open_clip_torch. Install with:\n"
        "  uv pip install -r tools/biocap/requirements.txt"
    ) from exc


TAXONOMIC_RANKS = ("genus", "family")
METRIC_KS = (1, 3, 10)


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
    parser.add_argument("--images", nargs="*", type=Path, default=[])
    parser.add_argument(
        "--image-manifest",
        type=Path,
        help="JSONL/CSV benchmark manifest. Relative paths resolve from its directory.",
    )
    parser.add_argument("--output", type=Path, help="Optional long-form rankings CSV path.")
    parser.add_argument("--report", type=Path, help="Optional benchmark report JSON path.")
    parser.add_argument("--top-k", type=int, default=10)
    parser.add_argument(
        "--device",
        choices=["auto", "cpu", "mps", "cuda"],
        default="auto",
        help="Torch device.",
    )
    return parser.parse_args()


def read_records(path: Path) -> list[dict[str, object]]:
    if path.suffix.lower() == ".jsonl":
        return [
            json.loads(line)
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
    if path.suffix.lower() == ".csv":
        with path.open(newline="", encoding="utf-8") as handle:
            return list(csv.DictReader(handle))
    raise SystemExit(f"Unsupported manifest format: {path}")


def load_cases(image_paths: list[Path], manifest: Path | None) -> list[dict[str, object]]:
    cases: list[dict[str, object]] = [
        {"imageID": str(path), "path": path} for path in image_paths
    ]
    if manifest:
        base = manifest.parent
        for index, record in enumerate(read_records(manifest), start=1):
            raw_path = record.get("path") or record.get("image") or record.get("imagePath")
            if not raw_path:
                raise SystemExit(f"Manifest row {index} is missing path")
            path = Path(str(raw_path))
            if not path.is_absolute():
                path = base / path
            case = dict(record)
            case["path"] = path
            case.setdefault("imageID", f"row-{index}")
            cases.append(case)
    if not cases:
        raise SystemExit("Pass at least one --images path or --image-manifest.")

    seen_ids: set[str] = set()
    for case in cases:
        image_id = str(case["imageID"])
        if image_id in seen_ids:
            raise SystemExit(f"Duplicate imageID in benchmark input: {image_id}")
        seen_ids.add(image_id)
        path = Path(case["path"])
        if not path.is_file():
            raise SystemExit(f"Benchmark image does not exist: {path}")
    return cases


def load_text_matrix(path: Path, species: list[Species]) -> tuple[np.ndarray, dict[str, object]]:
    with np.load(path) as data:
        if "embeddings" not in data.files:
            raise SystemExit(f"Embedding archive has no 'embeddings' array: {path}")
        embeddings = data["embeddings"].astype(np.float32)
        metadata = {
            key: data[key].tolist()
            for key in (
                "model_name",
                "prompt_preset",
                "prompt_templates",
                "label_text_type",
            )
            if key in data.files
        }
        if "scientific_names" not in data.files:
            raise SystemExit(
                "Embedding archive has no scientific_names array; row order cannot be verified."
            )
        embedded_names = [str(value) for value in data["scientific_names"].tolist()]

    expected_names = [item.scientific_name for item in species]
    if embedded_names != expected_names:
        mismatch = next(
            (
                index
                for index, (embedded, expected) in enumerate(
                    zip(embedded_names, expected_names, strict=False)
                )
                if embedded != expected
            ),
            min(len(embedded_names), len(expected_names)),
        )
        embedded = embedded_names[mismatch] if mismatch < len(embedded_names) else "<missing>"
        expected = expected_names[mismatch] if mismatch < len(expected_names) else "<missing>"
        raise SystemExit(
            f"Embedding/species row-order mismatch at index {mismatch}: "
            f"archive={embedded!r}, species-list={expected!r}"
        )
    if embeddings.shape != (len(species), 512):
        raise SystemExit(
            f"Embedding matrix shape {embeddings.shape} does not match "
            f"{len(species)} species rows."
        )
    if not np.isfinite(embeddings).all():
        raise SystemExit("Embedding matrix contains non-finite values.")
    norms = np.linalg.norm(embeddings, axis=1)
    if np.any(norms <= 0):
        raise SystemExit("Embedding matrix contains a zero-norm row.")
    embeddings /= norms[:, None]
    return embeddings, metadata


def rank_value(species: Species, rank: str) -> str:
    return species.genus if rank == "genus" else species.family


def expected_rank(scores: np.ndarray, expected_index: int) -> int:
    expected_score = scores[expected_index]
    return int(np.count_nonzero(scores > expected_score)) + 1


def taxonomic_hits(
    predictions: list[dict[str, object]],
    species_by_name: dict[str, Species],
    case: dict[str, object],
) -> dict[str, dict[str, bool | None]]:
    result: dict[str, dict[str, bool | None]] = {}
    for rank in TAXONOMIC_RANKS:
        expected = str(case.get(f"expected{rank.title()}") or "")
        if not expected:
            result[rank] = {f"top{k}": None for k in METRIC_KS}
            continue
        values = [
            rank_value(species_by_name[str(row["scientificName"])], rank)
            for row in predictions
        ]
        result[rank] = {
            f"top{k}": expected in values[:k]
            for k in METRIC_KS
        }
    return result


def mean(values: Iterable[float]) -> float | None:
    rows = list(values)
    return sum(rows) / len(rows) if rows else None


def percentile(values: list[float], percentile_value: float) -> float | None:
    if not values:
        return None
    return float(np.percentile(np.asarray(values, dtype=np.float64), percentile_value))


def metric_summary(rows: list[dict[str, object]]) -> dict[str, object]:
    in_catalog = [row for row in rows if row["inCatalog"]]
    out_of_catalog = [row for row in rows if not row["inCatalog"]]
    result: dict[str, object] = {
        "images": len(rows),
        "inCatalogImages": len(in_catalog),
        "outOfCatalogImages": len(out_of_catalog),
        "catalogCoverage": len(in_catalog) / len(rows) if rows else None,
        "forcedPredictionRateOnOutOfCatalog": 1.0 if out_of_catalog else None,
    }
    for k in METRIC_KS:
        result[f"speciesTop{k}All"] = mean(
            1.0 if row.get("expectedRank") and int(row["expectedRank"]) <= k else 0.0
            for row in rows
        )
        result[f"speciesTop{k}InCatalog"] = mean(
            1.0 if int(row["expectedRank"]) <= k else 0.0 for row in in_catalog
        )
    result["meanReciprocalRankAll"] = mean(
        1.0 / int(row["expectedRank"]) if row.get("expectedRank") else 0.0 for row in rows
    )
    result["meanReciprocalRankInCatalog"] = mean(
        1.0 / int(row["expectedRank"]) for row in in_catalog
    )
    for rank in TAXONOMIC_RANKS:
        for k in METRIC_KS:
            key = f"top{k}"
            eligible = [
                row for row in rows if row["taxonomicHits"][rank][key] is not None
            ]
            result[f"{rank}Top{k}"] = mean(
                1.0 if row["taxonomicHits"][rank][key] else 0.0 for row in eligible
            )
    return result


def grouped_summaries(
    rows: list[dict[str, object]], key: str
) -> dict[str, dict[str, object]]:
    grouped: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in rows:
        value = str(row.get(key) or "unspecified")
        grouped[value].append(row)
    return {value: metric_summary(group) for value, group in sorted(grouped.items())}


def peak_rss_bytes() -> int:
    value = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    # macOS reports bytes; Linux reports KiB.
    return int(value if platform.system() == "Darwin" else value * 1024)


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    if not rows:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    args = parse_args()
    if args.top_k < max(METRIC_KS):
        raise SystemExit(f"--top-k must be at least {max(METRIC_KS)} for benchmark metrics.")

    species = load_species(args.species_list)
    text_matrix, embedding_metadata = load_text_matrix(args.embeddings, species)
    cases = load_cases(args.images, args.image_manifest)
    species_by_name = {item.scientific_name: item for item in species}
    if len(species_by_name) != len(species):
        raise SystemExit("Species list contains duplicate scientific names.")
    species_index_by_name = {
        item.scientific_name: index for index, item in enumerate(species)
    }

    device = choose_device(args.device)
    print(f"loading {MODEL_NAME} on {device}")
    load_started = time.perf_counter()
    model, _, preprocess = open_clip.create_model_and_transforms(MODEL_NAME)
    model.to(device)
    model.eval()
    model_load_ms = (time.perf_counter() - load_started) * 1000

    result_rows: list[dict[str, object]] = []
    csv_rows: list[dict[str, object]] = []
    for index, case in enumerate(cases, start=1):
        image_path = Path(case["path"])
        encode_started = time.perf_counter()
        image_embedding = encode_image(model, preprocess, image_path, device).numpy()
        encode_ms = (time.perf_counter() - encode_started) * 1000
        score_started = time.perf_counter()
        scores = text_matrix @ image_embedding
        predictions = topk(scores, species, args.top_k)
        score_ms = (time.perf_counter() - score_started) * 1000

        expected_name = str(case.get("expectedScientificName") or "")
        expected_index = species_index_by_name.get(expected_name) if expected_name else None
        rank = expected_rank(scores, expected_index) if expected_index is not None else None
        row = {
            "imageID": str(case["imageID"]),
            "path": str(image_path),
            "datasetVersion": case.get("datasetVersion"),
            "expectedScientificName": expected_name or None,
            "evaluationGroup": case.get("evaluationGroup"),
            "region": case.get("region"),
            "caseTags": case.get("caseTags") or [],
            "inCatalog": expected_index is not None,
            "expectedRank": rank,
            "reciprocalRank": 1.0 / rank if rank else 0.0,
            "top1Top2Margin": (
                float(predictions[0]["score"]) - float(predictions[1]["score"])
                if len(predictions) > 1
                else None
            ),
            "encodeMs": encode_ms,
            "scoreMs": score_ms,
            "taxonomicHits": taxonomic_hits(predictions, species_by_name, case),
            "topK": predictions,
        }
        result_rows.append(row)
        for prediction in predictions:
            csv_rows.append(
                {
                    "imageID": row["imageID"],
                    "image": str(image_path),
                    "expectedScientificName": expected_name,
                    "inCatalog": row["inCatalog"],
                    "expectedRank": rank,
                    **prediction,
                }
            )
        print(
            f"[{index}/{len(cases)}] {row['imageID']}: "
            f"{predictions[0]['scientificName']} ({float(predictions[0]['score']):.4f})"
        )

    encode_times = [float(row["encodeMs"]) for row in result_rows]
    score_times = [float(row["scoreMs"]) for row in result_rows]
    report = {
        "schemaVersion": 1,
        "datasetVersion": next(
            (row.get("datasetVersion") for row in result_rows if row.get("datasetVersion")),
            None,
        ),
        "createdAtUnix": time.time(),
        "model": MODEL_NAME,
        "device": str(device),
        "catalog": {
            "speciesCount": len(species),
            "embeddingsPath": str(args.embeddings),
            "speciesListPath": str(args.species_list),
            "embeddingFileBytes": args.embeddings.stat().st_size,
            "speciesListFileBytes": args.species_list.stat().st_size,
            "metadata": embedding_metadata,
        },
        "summary": metric_summary(result_rows),
        "byGroup": grouped_summaries(result_rows, "evaluationGroup"),
        "byRegion": grouped_summaries(result_rows, "region"),
        "performance": {
            "modelLoadMs": model_load_ms,
            "encodeMeanMs": mean(encode_times),
            "encodeP50Ms": percentile(encode_times, 50),
            "encodeP95Ms": percentile(encode_times, 95),
            "scoreMeanMs": mean(score_times),
            "scoreP50Ms": percentile(score_times, 50),
            "scoreP95Ms": percentile(score_times, 95),
            "peakRSSBytes": peak_rss_bytes(),
        },
        "limitations": {
            "outOfCatalogRejectionImplemented": False,
            "peakMemoryMeasurement": "Process peak RSS; not iOS per-inference memory.",
            "bundleSizeMeasurement": "Embedding archive and species-list files only.",
        },
        "images": result_rows,
    }

    if args.output:
        write_csv(args.output, csv_rows)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if not args.report:
        print(json.dumps({"summary": report["summary"], "performance": report["performance"]}, indent=2))


if __name__ == "__main__":
    main()
