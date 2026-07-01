#!/usr/bin/env python3
"""Build a BirdNET/audio-overlap BioCAP candidate species list."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Create a JSONL species list from bundled Fieldnotes/BirdNET audio "
            "labels. Use make_image_species_list.py for image-native candidates."
        )
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="fieldnotes-ios checkout root.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Output JSONL path. Prints to stdout when omitted.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        help="Optional row limit for quick BioCAP parity smoke tests.",
    )
    parser.add_argument(
        "--scientific-name",
        action="append",
        default=[],
        help="Exact scientific name to include. May be repeated.",
    )
    return parser.parse_args()


def load_json(path: Path) -> dict[str, str]:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    args = parse_args()
    labels_dir = args.repo_root / "Fieldnotes" / "Fieldnotes" / "Resources" / "Labels"
    labels_path = labels_dir / "BirdNET_GLOBAL_6K_V2.4_Model_FP16_Labels.txt"
    common_names_path = labels_dir / "labels_en.json"
    taxa_path = labels_dir / "taxa.json"

    labels = [
        line.strip()
        for line in labels_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    common_names = load_json(common_names_path)
    taxa = load_json(taxa_path)

    selected_labels = args.scientific_name or labels
    missing = sorted(set(selected_labels) - set(labels))
    if missing:
        raise SystemExit(f"Scientific names not found in labels: {', '.join(missing)}")

    if args.limit and not args.scientific_name:
        selected_labels = selected_labels[: args.limit]

    rows = []
    for scientific_name in selected_labels:
        rows.append(
            {
                "scientificName": scientific_name,
                "commonName": common_names.get(scientific_name, scientific_name),
                "taxon": taxa.get(scientific_name, "bird"),
            }
        )

    output = "\n".join(json.dumps(row, sort_keys=True) for row in rows) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output, encoding="utf-8")
    else:
        print(output, end="")


if __name__ == "__main__":
    main()
