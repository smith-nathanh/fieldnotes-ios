#!/usr/bin/env python3
"""Build an image-native BioCAP candidate species list.

The image classifier is not limited to BirdNET/audio labels. This tool builds a
JSONL species list from BioCAP's wiki-species taxonomy export, with an optional
union of BirdNET labels so audio/photo overlap can still merge by scientific
name.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Iterable


WIKI_SOURCE = "biocap-wiki-species"
BIRDNET_SOURCE = "birdnet-audio-labels"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Create a JSONL species list from BioCAP wiki-species taxonomy. "
            "Taxonomy include filters are unioned, so --class-name Aves "
            "--order Coleoptera includes both birds and beetles. Exclude "
            "filters remove rows after inclusion."
        )
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="fieldnotes-ios checkout root.",
    )
    parser.add_argument(
        "--wiki-species-dir",
        type=Path,
        default=Path("tmp/biocap-source/data/wiki_species"),
        help="Directory containing BioCAP species_binomial_*.csv files.",
    )
    parser.add_argument(
        "--wiki-species-csv",
        action="append",
        type=Path,
        default=[],
        help="Specific BioCAP wiki-species CSV. May be repeated.",
    )
    parser.add_argument(
        "--include-ambiguous",
        action="store_true",
        help="Also include species_binomial_ambiguous.csv.",
    )
    parser.add_argument(
        "--include-birdnet",
        action="store_true",
        help="Union in Fieldnotes/BirdNET audio labels for overlap by scientific name.",
    )
    parser.add_argument("--kingdom", action="append", default=[], help="Exact kingdom filter.")
    parser.add_argument("--phylum", action="append", default=[], help="Exact phylum filter.")
    parser.add_argument(
        "--class-name",
        action="append",
        default=[],
        help="Exact class filter, e.g. Insecta or Aves.",
    )
    parser.add_argument("--order", action="append", default=[], help="Exact order filter.")
    parser.add_argument("--family", action="append", default=[], help="Exact family filter.")
    parser.add_argument("--genus", action="append", default=[], help="Exact genus filter.")
    parser.add_argument(
        "--exclude-kingdom",
        action="append",
        default=[],
        help="Exact kingdom to exclude after inclusion filters. May be repeated.",
    )
    parser.add_argument(
        "--exclude-phylum",
        action="append",
        default=[],
        help="Exact phylum to exclude after inclusion filters. May be repeated.",
    )
    parser.add_argument(
        "--exclude-class-name",
        action="append",
        default=[],
        help="Exact class to exclude after inclusion filters. May be repeated.",
    )
    parser.add_argument(
        "--exclude-order",
        action="append",
        default=[],
        help="Exact order to exclude after inclusion filters. May be repeated.",
    )
    parser.add_argument(
        "--exclude-family",
        action="append",
        default=[],
        help="Exact family to exclude after inclusion filters. May be repeated.",
    )
    parser.add_argument(
        "--exclude-genus",
        action="append",
        default=[],
        help="Exact genus to exclude after inclusion filters. May be repeated.",
    )
    parser.add_argument(
        "--scientific-name",
        action="append",
        default=[],
        help="Exact scientific name to include from wiki species. May be repeated.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        help="Optional row limit after sorting, for quick embedding smoke tests.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Output JSONL path. Prints to stdout when omitted.",
    )
    return parser.parse_args()


def normalized_values(values: Iterable[str]) -> set[str]:
    return {value.strip() for value in values if value.strip()}


def taxon_for(row: dict[str, str]) -> str:
    kingdom = row.get("kingdom", "")
    phylum = row.get("phylum", "")
    class_name = row.get("class", "")

    if class_name == "Aves":
        return "bird"
    if class_name == "Mammalia":
        return "mammal"
    if class_name == "Amphibia":
        return "amphibian"
    if class_name == "Reptilia":
        return "reptile"
    if class_name == "Insecta":
        return "insect"
    if phylum == "Arthropoda":
        return "arthropod"
    if kingdom == "Plantae":
        return "plant"
    if kingdom == "Fungi":
        return "fungi"
    return "unknown"


def record_for_wiki_row(row: dict[str, str]) -> dict[str, object]:
    scientific_name = row["binomial"].strip()
    return {
        "scientificName": scientific_name,
        "commonName": scientific_name,
        "taxon": taxon_for(row),
        "kingdom": row.get("kingdom", ""),
        "phylum": row.get("phylum", ""),
        "class": row.get("class", ""),
        "order": row.get("order", ""),
        "family": row.get("family", ""),
        "genus": row.get("genus", ""),
        "species": row.get("species", ""),
        "sources": [WIKI_SOURCE],
    }


def passes_filter(
    row: dict[str, str],
    *,
    kingdoms: set[str],
    phyla: set[str],
    class_names: set[str],
    orders: set[str],
    families: set[str],
    genera: set[str],
    exclude_kingdoms: set[str],
    exclude_phyla: set[str],
    exclude_class_names: set[str],
    exclude_orders: set[str],
    exclude_families: set[str],
    exclude_genera: set[str],
    scientific_names: set[str],
) -> bool:
    exclude_checks = [
        (exclude_kingdoms, row.get("kingdom", "")),
        (exclude_phyla, row.get("phylum", "")),
        (exclude_class_names, row.get("class", "")),
        (exclude_orders, row.get("order", "")),
        (exclude_families, row.get("family", "")),
        (exclude_genera, row.get("genus", "")),
    ]
    if any(value in excluded for excluded, value in exclude_checks if excluded):
        return False

    if scientific_names and row.get("binomial", "").strip() in scientific_names:
        return True
    checks = [
        (kingdoms, row.get("kingdom", "")),
        (phyla, row.get("phylum", "")),
        (class_names, row.get("class", "")),
        (orders, row.get("order", "")),
        (families, row.get("family", "")),
        (genera, row.get("genus", "")),
    ]
    active = [(allowed, value) for allowed, value in checks if allowed]
    if not active:
        return False
    return any(value in allowed for allowed, value in active)


def read_json(path: Path) -> dict[str, str]:
    return json.loads(path.read_text(encoding="utf-8"))


def add_source(record: dict[str, object], source: str) -> None:
    sources = record.setdefault("sources", [])
    if isinstance(sources, list) and source not in sources:
        sources.append(source)


def merge_record(
    records: dict[str, dict[str, object]], record: dict[str, object]
) -> None:
    scientific_name = str(record["scientificName"])
    existing = records.get(scientific_name)
    if existing is None:
        records[scientific_name] = record
        return

    if existing.get("commonName") == existing.get("scientificName"):
        common_name = record.get("commonName")
        if common_name:
            existing["commonName"] = common_name
    for source in record.get("sources", []):
        add_source(existing, str(source))
    for key, value in record.items():
        if key in {"scientificName", "commonName", "sources"}:
            continue
        if value and not existing.get(key):
            existing[key] = value


def wiki_csv_paths(args: argparse.Namespace) -> list[Path]:
    if args.wiki_species_csv:
        return args.wiki_species_csv

    wiki_dir = args.repo_root / args.wiki_species_dir
    paths = [wiki_dir / "species_binomial_unique.csv"]
    if args.include_ambiguous:
        paths.append(wiki_dir / "species_binomial_ambiguous.csv")
    return paths


def load_wiki_records(args: argparse.Namespace) -> dict[str, dict[str, object]]:
    kingdoms = normalized_values(args.kingdom)
    phyla = normalized_values(args.phylum)
    class_names = normalized_values(args.class_name)
    orders = normalized_values(args.order)
    families = normalized_values(args.family)
    genera = normalized_values(args.genus)
    exclude_kingdoms = normalized_values(args.exclude_kingdom)
    exclude_phyla = normalized_values(args.exclude_phylum)
    exclude_class_names = normalized_values(args.exclude_class_name)
    exclude_orders = normalized_values(args.exclude_order)
    exclude_families = normalized_values(args.exclude_family)
    exclude_genera = normalized_values(args.exclude_genus)
    scientific_names = normalized_values(args.scientific_name)

    records: dict[str, dict[str, object]] = {}
    for path in wiki_csv_paths(args):
        if not path.exists():
            raise SystemExit(f"BioCAP wiki-species CSV not found: {path}")
        with path.open(newline="", encoding="utf-8") as handle:
            for row in csv.DictReader(handle):
                if not row.get("binomial"):
                    continue
                if passes_filter(
                    row,
                    kingdoms=kingdoms,
                    phyla=phyla,
                    class_names=class_names,
                    orders=orders,
                    families=families,
                    genera=genera,
                    exclude_kingdoms=exclude_kingdoms,
                    exclude_phyla=exclude_phyla,
                    exclude_class_names=exclude_class_names,
                    exclude_orders=exclude_orders,
                    exclude_families=exclude_families,
                    exclude_genera=exclude_genera,
                    scientific_names=scientific_names,
                ):
                    merge_record(records, record_for_wiki_row(row))
    return records


def load_birdnet_records(repo_root: Path) -> dict[str, dict[str, object]]:
    labels_dir = repo_root / "Fieldnotes" / "Fieldnotes" / "Resources" / "Labels"
    labels_path = labels_dir / "BirdNET_GLOBAL_6K_V2.4_Model_FP16_Labels.txt"
    common_names = read_json(labels_dir / "labels_en.json")
    taxa = read_json(labels_dir / "taxa.json")

    records: dict[str, dict[str, object]] = {}
    labels = [
        line.strip()
        for line in labels_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    for scientific_name in labels:
        records[scientific_name] = {
            "scientificName": scientific_name,
            "commonName": common_names.get(scientific_name, scientific_name),
            "taxon": taxa.get(scientific_name, "bird"),
            "sources": [BIRDNET_SOURCE],
        }
    return records


def write_jsonl(path: Path | None, records: list[dict[str, object]]) -> None:
    output = "\n".join(json.dumps(record, sort_keys=True) for record in records)
    output += "\n" if output else ""
    if path is None:
        print(output, end="")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(output, encoding="utf-8")


def print_summary(records: list[dict[str, object]]) -> None:
    taxa = Counter(str(record.get("taxon", "unknown")) for record in records)
    classes = Counter(str(record.get("class", "")) for record in records if record.get("class"))
    orders = Counter(str(record.get("order", "")) for record in records if record.get("order"))
    birdnet_label_count = sum(
        1 for record in records if BIRDNET_SOURCE in record.get("sources", [])
    )
    summary = {
        "speciesCount": len(records),
        "birdnetLabelCount": birdnet_label_count,
        "topTaxa": dict(taxa.most_common(12)),
        "topClasses": dict(classes.most_common(12)),
        "topOrders": dict(orders.most_common(12)),
    }
    print(json.dumps(summary, indent=2, sort_keys=True), file=sys.stderr)


def main() -> None:
    args = parse_args()
    records = load_wiki_records(args)
    if args.include_birdnet:
        for record in load_birdnet_records(args.repo_root).values():
            merge_record(records, record)

    output_records = sorted(records.values(), key=lambda row: str(row["scientificName"]))
    if args.limit:
        output_records = output_records[: args.limit]
    if not output_records:
        raise SystemExit(
            "Species list is empty. Add a wiki filter such as --order Coleoptera "
            "or pass --include-birdnet."
        )

    write_jsonl(args.output, output_records)
    print_summary(output_records)


if __name__ == "__main__":
    main()
