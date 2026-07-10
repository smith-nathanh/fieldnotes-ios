#!/usr/bin/env python3
"""Audit a conservative species/genus/family policy on a BioCAP report."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--benchmark-report", type=Path, required=True)
    parser.add_argument("--species-list", type=Path, required=True)
    parser.add_argument("--image-manifest", type=Path, required=True)
    parser.add_argument("--exact-margin", type=float, default=0.035)
    parser.add_argument("--contender-delta", type=float, default=0.020)
    parser.add_argument("--regional-boost", type=float, default=0.005)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def read_jsonl(path: Path) -> list[dict[str, object]]:
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def normalized(value: object) -> str | None:
    text = str(value or "").strip()
    return text or None


def evaluate_case(
    predictions: list[dict[str, object]],
    metadata: dict[str, dict[str, object]],
    exact_margin: float,
    contender_delta: float,
    regional_boost: float = 0,
) -> dict[str, object]:
    ranked = []
    for prediction in predictions:
        row = metadata[str(prediction["scientificName"])]
        score = float(prediction["score"])
        ranking_score = score + (
            regional_boost if row.get("catalogTier") == "regional" else 0
        )
        ranked.append({**prediction, "rankingScore": ranking_score, "metadata": row})
    ranked.sort(key=lambda row: float(row["rankingScore"]), reverse=True)
    if not ranked:
        return {"rank": "uncertain", "name": None, "topScientificName": None}
    first = ranked[0]
    margin = (
        float(first["rankingScore"]) - float(ranked[1]["rankingScore"])
        if len(ranked) > 1
        else None
    )
    if margin is None or margin >= exact_margin:
        return {
            "rank": "species",
            "name": first["scientificName"],
            "topScientificName": first["scientificName"],
            "margin": margin,
        }
    contenders = [
        row
        for row in ranked
        if float(first["rankingScore"]) - float(row["rankingScore"]) <= contender_delta
    ]
    for rank in ("genus", "family"):
        values = {
            value
            for row in contenders
            if (value := normalized(row["metadata"].get(rank))) is not None
        }
        if len(contenders) > 1 and len(values) == 1:
            return {
                "rank": rank,
                "name": next(iter(values)),
                "topScientificName": first["scientificName"],
                "margin": margin,
            }
    return {
        "rank": "uncertain",
        "name": None,
        "topScientificName": first["scientificName"],
        "margin": margin,
    }


def precision_curve(images: list[dict[str, object]]) -> list[dict[str, object]]:
    curve = []
    for threshold in (0, 0.005, 0.010, 0.015, 0.020, 0.025, 0.030, 0.035, 0.040, 0.045):
        accepted = [row for row in images if float(row["top1Top2Margin"]) >= threshold]
        correct = sum(
            row["topK"][0]["scientificName"] == row["expectedScientificName"]
            for row in accepted
        )
        curve.append(
            {
                "margin": threshold,
                "acceptedImages": len(accepted),
                "coverage": len(accepted) / len(images) if images else None,
                "precision": correct / len(accepted) if accepted else None,
            }
        )
    return curve


def main() -> None:
    args = parse_args()
    benchmark = json.loads(args.benchmark_report.read_text())
    images = list(benchmark["images"])
    species_rows = read_jsonl(args.species_list)
    metadata = {str(row["scientificName"]): row for row in species_rows}
    manifest = {str(row["imageID"]): row for row in read_jsonl(args.image_manifest)}
    outcomes = []
    prior_changed_top1 = 0
    raw_top1_correct = 0
    contextual_top1_correct = 0
    for image in images:
        raw = evaluate_case(
            image["topK"], metadata, args.exact_margin, args.contender_delta
        )
        contextual = evaluate_case(
            image["topK"],
            metadata,
            args.exact_margin,
            args.contender_delta,
            args.regional_boost,
        )
        if raw["topScientificName"] != contextual["topScientificName"]:
            prior_changed_top1 += 1
        expected = manifest[str(image["imageID"])]
        expected_by_rank = {
            "species": image["expectedScientificName"],
            "genus": expected.get("expectedGenus"),
            "family": expected.get("expectedFamily"),
        }
        raw_top1_correct += raw["topScientificName"] == expected_by_rank["species"]
        contextual_top1_correct += contextual["topScientificName"] == expected_by_rank["species"]
        rank = str(contextual["rank"])
        contextual["correctAtSuggestedRank"] = (
            contextual["name"] == expected_by_rank.get(rank) if rank != "uncertain" else None
        )
        outcomes.append(contextual)

    counts = Counter(str(row["rank"]) for row in outcomes)
    supported = [row for row in outcomes if row["rank"] != "uncertain"]
    species = [row for row in outcomes if row["rank"] == "species"]
    result = {
        "schemaVersion": 1,
        "datasetVersion": benchmark.get("datasetVersion"),
        "images": len(images),
        "policy": {
            "exactSpeciesMargin": args.exact_margin,
            "contenderDelta": args.contender_delta,
            "northCarolinaRegionalBoost": args.regional_boost,
            "rawSimilarityIsCalibratedProbability": False,
        },
        "outcomes": dict(sorted(counts.items())),
        "speciesDecision": {
            "acceptedImages": len(species),
            "coverage": len(species) / len(images) if images else None,
            "precision": (
                sum(bool(row["correctAtSuggestedRank"]) for row in species) / len(species)
                if species
                else None
            ),
        },
        "supportedRankDecision": {
            "images": len(supported),
            "coverage": len(supported) / len(images) if images else None,
            "accuracyAtSuggestedRank": (
                sum(bool(row["correctAtSuggestedRank"]) for row in supported) / len(supported)
                if supported
                else None
            ),
        },
        "northCarolinaPrior": {
            "top1ChangesWithinAvailableTop10": prior_changed_top1,
            "rawTop1Accuracy": raw_top1_correct / len(images) if images else None,
            "contextualTop1Accuracy": contextual_top1_correct / len(images) if images else None,
            "top1AccuracyDelta": (
                (contextual_top1_correct - raw_top1_correct) / len(images)
                if images
                else None
            ),
            "note": "The boost is positive-only; travel-tier rows remain eligible.",
        },
        "speciesMarginCurve": precision_curve(images),
        "limitations": [
            "The policy was selected and measured on the same 60-image pilot set; it is not held-out calibration.",
            "The dataset contains animals only, so out-of-catalog rejection cannot be measured here.",
            "The regional prior audit reranks the recorded top 10, not the entire matrix.",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
