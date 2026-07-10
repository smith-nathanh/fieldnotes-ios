#!/usr/bin/env python3
"""Convert a BioCAP text archive to float16 and measure numerical/ranking drift."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="Canonical float32 NPZ.")
    parser.add_argument("--output", type=Path, required=True, help="Float16 NPZ to write.")
    parser.add_argument("--report", type=Path, required=True, help="JSON comparison report.")
    parser.add_argument(
        "--query-embeddings",
        type=Path,
        help=(
            "Optional NPZ with a 2D embeddings array of normalized image queries. "
            "When supplied, report top-1, ordered top-k, and top-k set parity."
        ),
    )
    parser.add_argument("--top-k", type=int, default=10)
    return parser.parse_args()


def normalized_rows(matrix: np.ndarray, label: str) -> np.ndarray:
    matrix = np.asarray(matrix, dtype=np.float32)
    if matrix.ndim != 2 or not matrix.size:
        raise SystemExit(f"{label} must be a non-empty 2D matrix.")
    if not np.isfinite(matrix).all():
        raise SystemExit(f"{label} contains non-finite values.")
    norms = np.linalg.norm(matrix, axis=1)
    if np.any(norms <= 0):
        raise SystemExit(f"{label} contains a zero-norm row.")
    return matrix / norms[:, None]


def ranking_parity(
    reference: np.ndarray,
    quantized: np.ndarray,
    queries: np.ndarray,
    top_k: int,
) -> dict[str, object]:
    if top_k <= 0 or top_k > reference.shape[0]:
        raise SystemExit("top-k must be between 1 and the catalog row count.")
    queries = normalized_rows(queries, "Query embeddings")
    reference_scores = queries @ reference.T
    quantized_scores = queries @ quantized.T
    reference_order = np.argsort(-reference_scores, axis=1, kind="stable")[:, :top_k]
    quantized_order = np.argsort(-quantized_scores, axis=1, kind="stable")[:, :top_k]
    ordered_matches = np.all(reference_order == quantized_order, axis=1)
    set_matches = np.asarray(
        [
            set(reference_row.tolist()) == set(quantized_row.tolist())
            for reference_row, quantized_row in zip(
                reference_order, quantized_order, strict=True
            )
        ]
    )
    top1_matches = reference_order[:, 0] == quantized_order[:, 0]
    return {
        "queryCount": int(queries.shape[0]),
        "topK": top_k,
        "top1Matches": int(top1_matches.sum()),
        "top1Parity": float(top1_matches.mean()),
        "orderedTopKMatches": int(ordered_matches.sum()),
        "orderedTopKParity": float(ordered_matches.mean()),
        "topKSetMatches": int(set_matches.sum()),
        "topKSetParity": float(set_matches.mean()),
        "maximumScoreDelta": float(
            np.max(np.abs(reference_scores - quantized_scores))
        ),
    }


def quantize_archive(
    input_path: Path,
    output_path: Path,
    query_path: Path | None = None,
    top_k: int = 10,
) -> dict[str, object]:
    with np.load(input_path) as archive:
        if "embeddings" not in archive.files:
            raise SystemExit("Input archive has no embeddings array.")
        arrays = {key: archive[key] for key in archive.files}

    original = np.asarray(arrays["embeddings"])
    if original.dtype != np.float32:
        raise SystemExit(f"Canonical input must be float32, found {original.dtype}.")
    reference = normalized_rows(original, "Text embeddings")
    quantized_raw = original.astype(np.float16)
    dequantized = quantized_raw.astype(np.float32)
    quantized_normalized = normalized_rows(dequantized, "Quantized text embeddings")
    arrays["embeddings"] = quantized_raw

    output_path.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(output_path, **arrays)

    element_delta = np.abs(original - dequantized)
    quantized_norms = np.linalg.norm(dequantized, axis=1)
    row_cosines = np.sum(reference * quantized_normalized, axis=1)
    report: dict[str, object] = {
        "input": str(input_path),
        "output": str(output_path),
        "shape": list(original.shape),
        "inputDtype": str(original.dtype),
        "outputDtype": str(quantized_raw.dtype),
        "inputBytes": int(original.nbytes),
        "outputBytes": int(quantized_raw.nbytes),
        "maximumAbsoluteElementError": float(element_delta.max()),
        "meanAbsoluteElementError": float(element_delta.mean()),
        "quantizedNormMinimum": float(quantized_norms.min()),
        "quantizedNormMaximum": float(quantized_norms.max()),
        "rowCosineMinimum": float(row_cosines.min()),
        "rowCosineMean": float(row_cosines.mean()),
        "rankingParity": None,
    }
    if query_path is not None:
        with np.load(query_path) as query_archive:
            if "embeddings" not in query_archive.files:
                raise SystemExit("Query archive has no embeddings array.")
            queries = query_archive["embeddings"]
        if queries.shape[1] != original.shape[1]:
            raise SystemExit("Query embedding dimension does not match text embeddings.")
        report["rankingParity"] = ranking_parity(
            original, dequantized, queries, top_k
        )
    return report


def main() -> None:
    args = parse_args()
    report = quantize_archive(
        args.input,
        args.output,
        query_path=args.query_embeddings,
        top_k=args.top_k,
    )
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
