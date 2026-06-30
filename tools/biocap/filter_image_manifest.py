#!/usr/bin/env python3
"""Filter a BioCAP image manifest to labels present in a species list."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--species-list",
        type=Path,
        required=True,
        help="JSONL/JSON/CSV species list with scientificName.",
    )
    parser.add_argument(
        "--image-manifest",
        type=Path,
        required=True,
        help="JSONL/CSV image manifest with expectedScientificName.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Filtered JSONL manifest output path.",
    )
    parser.add_argument(
        "--write-missing",
        type=Path,
        help="Optional JSONL output for excluded manifest rows.",
    )
    return parser.parse_args()


def read_records(path: Path) -> list[dict[str, object]]:
    suffix = path.suffix.lower()
    if suffix == ".jsonl":
        return [
            json.loads(line)
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
    if suffix == ".json":
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, list):
            raise SystemExit(f"Expected JSON array in {path}")
        return data
    if suffix == ".csv":
        with path.open(newline="", encoding="utf-8") as handle:
            return list(csv.DictReader(handle))
    raise SystemExit(f"Unsupported input format: {path}")


def scientific_names(records: list[dict[str, object]]) -> set[str]:
    names = set()
    for record in records:
        name = record.get("scientificName") or record.get("scientific_name")
        if not name:
            raise SystemExit(f"Species row missing scientificName: {record}")
        names.add(str(name))
    return names


def expected_name(record: dict[str, object]) -> str:
    name = (
        record.get("expectedScientificName")
        or record.get("scientificName")
        or record.get("expected_scientific_name")
    )
    if not name:
        raise SystemExit(f"Manifest row missing expectedScientificName: {record}")
    return str(name)


def write_jsonl(path: Path, records: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    output = "\n".join(json.dumps(record, sort_keys=True) for record in records)
    path.write_text(output + ("\n" if output else ""), encoding="utf-8")


def main() -> None:
    args = parse_args()
    included_names = scientific_names(read_records(args.species_list))
    manifest_rows = read_records(args.image_manifest)

    kept = []
    missing = []
    for row in manifest_rows:
        if expected_name(row) in included_names:
            kept.append(row)
        else:
            missing.append(row)

    write_jsonl(args.output, kept)
    if args.write_missing:
        write_jsonl(args.write_missing, missing)

    print(
        json.dumps(
            {
                "inputImages": len(manifest_rows),
                "keptImages": len(kept),
                "excludedImages": len(missing),
                "speciesCount": len(included_names),
            },
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
