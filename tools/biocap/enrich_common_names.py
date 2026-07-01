#!/usr/bin/env python3
"""Enrich BioCAP species JSONL with English common names.

This is an offline build step. It preserves row order so the enriched JSONL can
be used with an existing text-embedding matrix.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import Counter
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--species-list",
        type=Path,
        required=True,
        help="Input JSONL species list. Row order is preserved.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Output enriched JSONL path.",
    )
    parser.add_argument(
        "--birdnet-common-names",
        type=Path,
        default=Path("Fieldnotes/Fieldnotes/Resources/Labels/labels_en.json"),
        help="BirdNET scientific-name to common-name JSON.",
    )
    parser.add_argument(
        "--manual-overrides",
        type=Path,
        default=Path("tools/biocap/common_name_overrides.json"),
        help="Manual scientific-name to English common-name JSON.",
    )
    parser.add_argument(
        "--vernacular-jsonl",
        action="append",
        default=[],
        type=Path,
        help=(
            "Optional external JSONL vernacular source. Rows may use "
            "scientificName/canonicalName and commonName/vernacularName. "
            "English rows are preferred when a language field is present."
        ),
    )
    parser.add_argument(
        "--vernacular-csv",
        action="append",
        default=[],
        type=Path,
        help="Optional external CSV vernacular source with similar columns.",
    )
    parser.add_argument(
        "--replace-existing",
        action="store_true",
        help="Replace non-scientific existing commonName values.",
    )
    return parser.parse_args()


def load_json(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    return {str(key): str(value) for key, value in data.items() if value}


def read_jsonl(path: Path) -> list[dict[str, object]]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    output = "\n".join(json.dumps(row, sort_keys=True) for row in rows)
    path.write_text(output + ("\n" if output else ""), encoding="utf-8")


def is_english(record: dict[str, object]) -> bool:
    language = str(
        record.get("language")
        or record.get("lang")
        or record.get("locale")
        or record.get("languageCode")
        or ""
    ).lower()
    return not language or language in {"en", "eng", "english"}


def name_fields(record: dict[str, object]) -> tuple[str | None, str | None]:
    scientific_name = (
        record.get("scientificName")
        or record.get("scientific_name")
        or record.get("canonicalName")
        or record.get("taxon_name")
        or record.get("name")
    )
    common_name = (
        record.get("commonName")
        or record.get("common_name")
        or record.get("vernacularName")
        or record.get("vernacular_name")
        or record.get("preferred_common_name")
    )
    if not scientific_name or not common_name:
        return None, None
    return str(scientific_name).strip(), str(common_name).strip()


def add_vernacular(mapping: dict[str, str], record: dict[str, object]) -> None:
    if not is_english(record):
        return
    scientific_name, common_name = name_fields(record)
    if scientific_name and common_name and scientific_name not in mapping:
        mapping[scientific_name] = common_name


def load_vernacular_sources(jsonl_paths: list[Path], csv_paths: list[Path]) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for path in jsonl_paths:
        for record in read_jsonl(path):
            add_vernacular(mapping, record)
    for path in csv_paths:
        with path.open(newline="", encoding="utf-8") as handle:
            for record in csv.DictReader(handle):
                add_vernacular(mapping, record)
    return mapping


def binomial(scientific_name: str) -> str | None:
    parts = scientific_name.split()
    if len(parts) < 3:
        return None
    return " ".join(parts[:2])


def needs_common_name(row: dict[str, object], replace_existing: bool) -> bool:
    scientific_name = str(row["scientificName"])
    common_name = str(row.get("commonName") or "")
    return replace_existing or not common_name or common_name == scientific_name


def enrich_row(
    row: dict[str, object],
    *,
    exact_names: dict[str, str],
    parent_names: dict[str, str],
    replace_existing: bool,
) -> str:
    scientific_name = str(row["scientificName"])
    if not needs_common_name(row, replace_existing):
        return "kept"

    if scientific_name in exact_names:
        row["commonName"] = exact_names[scientific_name]
        return "exact"

    parent = binomial(scientific_name)
    if parent and parent in parent_names:
        row["commonName"] = parent_names[parent]
        row["commonNameSourceScientificName"] = parent
        return "parent"

    row["commonName"] = scientific_name
    return "fallback"


def main() -> None:
    args = parse_args()
    rows = read_jsonl(args.species_list)
    birdnet_names = load_json(args.birdnet_common_names)
    manual_names = load_json(args.manual_overrides)
    vernacular_names = load_vernacular_sources(args.vernacular_jsonl, args.vernacular_csv)

    exact_names: dict[str, str] = {}
    exact_names.update(vernacular_names)
    exact_names.update(birdnet_names)
    exact_names.update(manual_names)

    parent_names = {
        name: common
        for name, common in exact_names.items()
        if len(name.split()) == 2
    }

    counts: Counter[str] = Counter()
    for row in rows:
        if not row.get("scientificName"):
            raise SystemExit(f"Species row missing scientificName: {row}")
        source = enrich_row(
            row,
            exact_names=exact_names,
            parent_names=parent_names,
            replace_existing=args.replace_existing,
        )
        counts[source] += 1

    write_jsonl(args.output, rows)
    print(
        json.dumps(
            {
                "inputRows": len(rows),
                "output": str(args.output),
                "sources": dict(sorted(counts.items())),
                "exactNameCount": len(exact_names),
                "parentFallbackNameCount": len(parent_names),
            },
            indent=2,
            sort_keys=True,
        ),
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
