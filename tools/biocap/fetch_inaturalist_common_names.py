#!/usr/bin/env python3
"""Fetch iNaturalist preferred English common names for a BioCAP species list.

This is an offline build helper. It pages major iNaturalist taxa, caches raw API
responses, and emits JSONL records that can be passed to enrich_common_names.py
with --vernacular-jsonl.
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


INAT_TAXA_URL = "https://api.inaturalist.org/v1/taxa"
DEFAULT_TAXA = {
    "Aves": 3,
    "Mammalia": 40151,
    "Amphibia": 20978,
    "Reptilia": 26036,
    "Coleoptera": 47208,
    "Odonata": 47792,
    "Orthoptera": 47651,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--species-list",
        type=Path,
        required=True,
        help="BioCAP species JSONL. Only exact names from this list are emitted.",
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
        default=Path("tmp/biocap-validation/inaturalist-taxa-cache"),
        help="Directory for cached iNaturalist API pages.",
    )
    parser.add_argument(
        "--taxon-id",
        action="append",
        default=[],
        help=(
            "iNaturalist taxon to page as NAME=ID or ID. Defaults to the current "
            "animal-only image candidate groups."
        ),
    )
    parser.add_argument(
        "--per-page",
        type=int,
        default=200,
        help="iNaturalist page size. The public API currently caps this at 200.",
    )
    parser.add_argument(
        "--sleep",
        type=float,
        default=0.15,
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
            label, raw_id = value.split("=", 1)
        else:
            raw_id = value
            label = value
        taxa[label.strip() or raw_id.strip()] = int(raw_id)
    return taxa


def cache_path(cache_dir: Path, label: str, taxon_id: int, page: int, id_above: int) -> Path:
    safe_label = "".join(char if char.isalnum() else "_" for char in label)
    return cache_dir / f"{safe_label}_{taxon_id}_above_{id_above:010d}_page_{page:05d}.json"


def fetch_json(url: str, *, retries: int = 3) -> dict[str, object]:
    headers = {
        "Accept": "application/json",
        "User-Agent": "fieldnotes-biocap-common-name-enrichment/1.0",
    }
    request = urllib.request.Request(url, headers=headers)
    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
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
    taxon_id: int,
    page: int,
    per_page: int,
    id_above: int,
    refresh: bool,
    sleep_seconds: float,
) -> dict[str, object]:
    path = cache_path(cache_dir, label, taxon_id, page, id_above)
    if path.exists() and not refresh:
        return json.loads(path.read_text(encoding="utf-8"))

    params = {
        "taxon_id": str(taxon_id),
        "rank": "species",
        "per_page": str(per_page),
        "page": str(page),
        "locale": "en",
        "order_by": "id",
        "order": "asc",
    }
    if id_above:
        params["id_above"] = str(id_above)
    url = f"{INAT_TAXA_URL}?{urllib.parse.urlencode(params)}"
    data = fetch_json(url)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, sort_keys=True), encoding="utf-8")
    if sleep_seconds > 0:
        time.sleep(sleep_seconds)
    return data


def output_record(taxon: dict[str, object], *, source_group: str) -> dict[str, object] | None:
    scientific_name = str(taxon.get("name") or "").strip()
    common_name = str(taxon.get("preferred_common_name") or "").strip()
    if not scientific_name or not common_name:
        return None
    return {
        "scientificName": scientific_name,
        "commonName": common_name,
        "language": "en",
        "source": "iNaturalist",
        "sourceGroup": source_group,
        "sourceTaxonId": taxon.get("id"),
        "observationsCount": taxon.get("observations_count"),
        "iconicTaxonName": taxon.get("iconic_taxon_name"),
    }


def write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    output = "\n".join(json.dumps(row, sort_keys=True) for row in rows)
    path.write_text(output + ("\n" if output else ""), encoding="utf-8")


def main() -> None:
    args = parse_args()
    wanted_names = read_species_names(args.species_list)
    taxa = parse_taxa(args.taxon_id)
    matches: dict[str, dict[str, object]] = {}
    pages_read = 0

    for label, taxon_id in taxa.items():
        id_above = 0
        taxon_pages = 0
        while True:
            page = 1
            max_seen_id = id_above
            while True:
                data = read_or_fetch_page(
                    cache_dir=args.cache_dir,
                    label=label,
                    taxon_id=taxon_id,
                    page=page,
                    per_page=args.per_page,
                    id_above=id_above,
                    refresh=args.refresh,
                    sleep_seconds=args.sleep,
                )
                pages_read += 1
                taxon_pages += 1
                results = data.get("results") or []
                if not isinstance(results, list):
                    raise SystemExit(
                        f"Unexpected iNaturalist results shape for {label} page {page}"
                    )
                if not results:
                    break

                for taxon in results:
                    if not isinstance(taxon, dict):
                        continue
                    taxon_id_value = taxon.get("id")
                    if isinstance(taxon_id_value, int):
                        max_seen_id = max(max_seen_id, taxon_id_value)

                    scientific_name = str(taxon.get("name") or "").strip()
                    if scientific_name not in wanted_names or scientific_name in matches:
                        continue
                    record = output_record(taxon, source_group=label)
                    if record:
                        matches[scientific_name] = record

                total = int(data.get("total_results") or 0)
                per_page = int(data.get("per_page") or args.per_page)
                if page * per_page >= total:
                    break
                if page * per_page >= 10_000:
                    break
                if args.max_pages and taxon_pages >= args.max_pages:
                    break
                page += 1

            if max_seen_id <= id_above:
                break
            if args.max_pages and taxon_pages >= args.max_pages:
                break
            id_above = max_seen_id

        print(
            json.dumps(
                {
                    "sourceGroup": label,
                    "taxonId": taxon_id,
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
