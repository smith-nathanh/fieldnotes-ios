#!/usr/bin/env python3
"""Fetch GBIF English vernacular names for a BioCAP species list.

This is an offline build helper. It pages GBIF species search by vetted higher
taxon keys and emits JSONL records compatible with enrich_common_names.py
--vernacular-jsonl.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Iterable


GBIF_SPECIES_SEARCH_URL = "https://api.gbif.org/v1/species/search"
DEFAULT_TAXA = {
    "Aves": 212,
    "Mammalia": 359,
    "Amphibia": 131,
    "Squamata": 11592253,
    "Testudines": 11418114,
    "Crocodylia": 11493978,
    "Sphenodontia": 11569602,
    "Coleoptera": 1470,
    "Odonata": 789,
    "Orthoptera": 1458,
}
ENGLISH_CODES = {"en", "eng", "english"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--species-list",
        type=Path,
        required=True,
        help="BioCAP species JSONL. Only exact canonical names from this list are emitted.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Output JSONL path for enrich_common_names.py --vernacular-jsonl.",
    )
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=Path("tmp/biocap-validation/gbif-species-cache"),
        help="Directory for cached GBIF API pages.",
    )
    parser.add_argument(
        "--taxon-key",
        action="append",
        default=[],
        help=(
            "GBIF higher taxon to page as NAME=KEY or KEY. Defaults to the "
            "current animal-only image candidate groups."
        ),
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=1000,
        help="GBIF page size.",
    )
    parser.add_argument(
        "--sleep",
        type=float,
        default=0.05,
        help="Seconds to sleep between uncached API requests.",
    )
    parser.add_argument(
        "--max-pages",
        type=int,
        help="Optional per-taxon page cap for smoke tests.",
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="Ignore cached API pages.",
    )
    return parser.parse_args()


def read_species_names(path: Path) -> set[str]:
    names: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        scientific_name = str(row.get("scientificName") or "").strip()
        if scientific_name:
            names.add(scientific_name)
    return names


def parse_taxa(values: Iterable[str]) -> dict[str, int]:
    if not values:
        return DEFAULT_TAXA

    taxa: dict[str, int] = {}
    for value in values:
        if "=" in value:
            label, raw_key = value.split("=", 1)
        else:
            raw_key = value
            label = value
        taxa[label.strip() or raw_key.strip()] = int(raw_key)
    return taxa


def cache_path(cache_dir: Path, label: str, taxon_key: int, offset: int) -> Path:
    safe_label = "".join(char if char.isalnum() else "_" for char in label)
    return cache_dir / f"{safe_label}_{taxon_key}_offset_{offset:07d}.json"


def fetch_json(url: str, *, retries: int = 3) -> dict[str, object]:
    headers = {
        "Accept": "application/json",
        "User-Agent": "fieldnotes-biocap-gbif-common-name-enrichment/1.0",
    }
    request = urllib.request.Request(url, headers=headers)
    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                return json.loads(response.read().decode("utf-8"))
        except (urllib.error.URLError, TimeoutError) as exc:
            if attempt == retries:
                raise RuntimeError(f"failed to fetch {url}: {exc}") from exc
            time.sleep(attempt)
    raise AssertionError("unreachable")


def read_or_fetch_page(
    *,
    cache_dir: Path,
    label: str,
    taxon_key: int,
    offset: int,
    limit: int,
    refresh: bool,
    sleep_seconds: float,
) -> dict[str, object]:
    path = cache_path(cache_dir, label, taxon_key, offset)
    if path.exists() and not refresh:
        return json.loads(path.read_text(encoding="utf-8"))

    params = {
        "higherTaxonKey": str(taxon_key),
        "rank": "SPECIES",
        "status": "ACCEPTED",
        "offset": str(offset),
        "limit": str(limit),
    }
    url = f"{GBIF_SPECIES_SEARCH_URL}?{urllib.parse.urlencode(params)}"
    data = fetch_json(url)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, sort_keys=True), encoding="utf-8")
    if sleep_seconds > 0:
        time.sleep(sleep_seconds)
    return data


def english_names(taxon: dict[str, object]) -> list[str]:
    names: list[str] = []
    for item in taxon.get("vernacularNames") or []:
        if not isinstance(item, dict):
            continue
        language = str(item.get("language") or "").strip().lower()
        if language not in ENGLISH_CODES:
            continue
        name = str(item.get("vernacularName") or "").strip()
        if name and name not in names:
            names.append(name)
    return names


def output_record(taxon: dict[str, object], *, source_group: str) -> dict[str, object] | None:
    scientific_name = str(taxon.get("canonicalName") or "").strip()
    names = english_names(taxon)
    if not scientific_name or not names:
        return None
    return {
        "scientificName": scientific_name,
        "commonName": names[0],
        "language": "eng",
        "source": "GBIF",
        "sourceGroup": source_group,
        "sourceTaxonKey": taxon.get("key"),
        "gbifScientificName": taxon.get("scientificName"),
        "gbifAlternates": names[1:],
    }


def write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    output = "\n".join(json.dumps(row, sort_keys=True) for row in rows)
    path.write_text(output + ("\n" if output else ""), encoding="utf-8")


def main() -> None:
    args = parse_args()
    wanted_names = read_species_names(args.species_list)
    taxa = parse_taxa(args.taxon_key)
    matches: dict[str, dict[str, object]] = {}
    pages_read = 0

    for label, taxon_key in taxa.items():
        offset = 0
        taxon_pages = 0
        while True:
            data = read_or_fetch_page(
                cache_dir=args.cache_dir,
                label=label,
                taxon_key=taxon_key,
                offset=offset,
                limit=args.limit,
                refresh=args.refresh,
                sleep_seconds=args.sleep,
            )
            pages_read += 1
            taxon_pages += 1
            results = data.get("results") or []
            if not isinstance(results, list):
                raise SystemExit(f"Unexpected GBIF results shape for {label} offset {offset}")

            for taxon in results:
                if not isinstance(taxon, dict):
                    continue
                scientific_name = str(taxon.get("canonicalName") or "").strip()
                if scientific_name not in wanted_names or scientific_name in matches:
                    continue
                record = output_record(taxon, source_group=label)
                if record:
                    matches[scientific_name] = record

            if bool(data.get("endOfRecords")):
                break
            page_limit = int(data.get("limit") or args.limit)
            if page_limit <= 0:
                break
            if args.max_pages and taxon_pages >= args.max_pages:
                break
            offset += page_limit

        print(
            json.dumps(
                {
                    "sourceGroup": label,
                    "taxonKey": taxon_key,
                    "pagesRead": taxon_pages,
                    "matchesSoFar": len(matches),
                },
                sort_keys=True,
            ),
            file=sys.stderr,
        )

    rows = [matches[name] for name in sorted(matches)]
    write_jsonl(args.output, rows)
    print(
        json.dumps(
            {
                "speciesList": str(args.species_list),
                "wantedSpecies": len(wanted_names),
                "output": str(args.output),
                "matchedCommonNames": len(rows),
                "pagesRead": pages_read,
            },
            indent=2,
            sort_keys=True,
        ),
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
