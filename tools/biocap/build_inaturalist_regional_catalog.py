#!/usr/bin/env python3
"""Build a hierarchical regional animal catalog from iNaturalist observations."""

from __future__ import annotations

import argparse
import hashlib
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path
from typing import Iterable


SPECIES_COUNTS_URL = "https://api.inaturalist.org/v1/observations/species_counts"
TAXA_URL = "https://api.inaturalist.org/v1/taxa"
USER_AGENT = "Fieldnotes-BioCAP-regional-catalog/1.0"
RANKS = ("kingdom", "phylum", "class", "order", "family", "genus", "species")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--definition",
        type=Path,
        default=Path("tools/biocap/catalogs/nc-regional-v1.json"),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("tmp/biocap-catalogs/nc-regional-v1/species.jsonl"),
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=Path("tmp/biocap-catalogs/nc-regional-v1/report.json"),
    )
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=Path("tmp/biocap-catalogs/inaturalist-cache"),
    )
    parser.add_argument("--sleep-seconds", type=float, default=1.0)
    parser.add_argument("--per-page", type=int, default=200)
    parser.add_argument("--taxonomy-batch-size", type=int, default=30)
    parser.add_argument(
        "--max-pages",
        type=int,
        help="Optional per-iconic-taxon page cap for smoke tests.",
    )
    parser.add_argument("--refresh", action="store_true")
    return parser.parse_args()


def fetch_json(url: str, retries: int = 3) -> dict[str, object]:
    request = urllib.request.Request(
        url,
        headers={"Accept": "application/json", "User-Agent": USER_AGENT},
    )
    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            if error.code != 429 and error.code < 500:
                raise
            last_error: Exception = error
        except (urllib.error.URLError, TimeoutError) as error:
            last_error = error
        if attempt < retries:
            time.sleep(attempt * 2)
    raise RuntimeError(f"Failed to fetch after {retries} attempts: {url}") from last_error


def read_or_fetch(path: Path, url: str, *, refresh: bool, sleep_seconds: float) -> dict[str, object]:
    if path.exists() and not refresh:
        return json.loads(path.read_text(encoding="utf-8"))
    data = fetch_json(url)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, sort_keys=True), encoding="utf-8")
    if sleep_seconds > 0:
        time.sleep(sleep_seconds)
    return data


def safe_key(value: str) -> str:
    return "".join(character.lower() if character.isalnum() else "-" for character in value).strip("-")


def species_count_page(
    *,
    cache_dir: Path,
    iconic_taxon: str,
    place_id: int,
    cutoff_date: str,
    page: int,
    per_page: int,
    refresh: bool,
    sleep_seconds: float,
) -> dict[str, object]:
    params = {
        "place_id": place_id,
        "quality_grade": "research",
        "verifiable": "true",
        "rank": "species",
        "iconic_taxa": iconic_taxon,
        "d2": cutoff_date,
        "page": page,
        "per_page": per_page,
    }
    url = f"{SPECIES_COUNTS_URL}?{urllib.parse.urlencode(params)}"
    scope = f"place-{place_id}-through-{cutoff_date}-per-{per_page}"
    path = (
        cache_dir
        / "species-counts"
        / safe_key(scope)
        / f"{safe_key(iconic_taxon)}-page-{page:04d}.json"
    )
    return read_or_fetch(path, url, refresh=refresh, sleep_seconds=sleep_seconds)


def load_species_counts(
    definition: dict[str, object],
    *,
    cache_dir: Path,
    per_page: int,
    max_pages: int | None,
    refresh: bool,
    sleep_seconds: float,
) -> tuple[dict[int, dict[str, object]], dict[str, int]]:
    records: dict[int, dict[str, object]] = {}
    pages_by_group: dict[str, int] = {}
    for iconic_taxon in definition["iconicTaxa"]:
        page = 1
        group_pages = 0
        while True:
            data = species_count_page(
                cache_dir=cache_dir,
                iconic_taxon=str(iconic_taxon),
                place_id=int(definition["placeID"]),
                cutoff_date=str(definition["cutoffDate"]),
                page=page,
                per_page=per_page,
                refresh=refresh,
                sleep_seconds=sleep_seconds,
            )
            group_pages += 1
            results = data.get("results") or []
            if not isinstance(results, list):
                raise SystemExit(f"Unexpected species-count response for {iconic_taxon} page {page}")
            for result in results:
                if not isinstance(result, dict) or not isinstance(result.get("taxon"), dict):
                    continue
                taxon = dict(result["taxon"])
                if taxon.get("rank") != "species" or not taxon.get("is_active", True):
                    continue
                count = int(result.get("count") or 0)
                if count < int(definition["minimumResearchObservations"]):
                    continue
                taxon["regional_observations_count"] = count
                records[int(taxon["id"])] = taxon
            total = int(data.get("total_results") or 0)
            if not results or page * per_page >= total:
                break
            if max_pages and group_pages >= max_pages:
                break
            page += 1
        pages_by_group[str(iconic_taxon)] = group_pages
        print(
            json.dumps(
                {
                    "iconicTaxon": iconic_taxon,
                    "pages": group_pages,
                    "speciesSoFar": len(records),
                },
                sort_keys=True,
            )
        )
    return records, pages_by_group


def batched(values: list[int], size: int) -> Iterable[list[int]]:
    for start in range(0, len(values), size):
        yield values[start : start + size]


def load_taxa(
    ids: set[int],
    *,
    cache_dir: Path,
    batch_size: int,
    refresh: bool,
    sleep_seconds: float,
) -> dict[int, dict[str, object]]:
    taxa: dict[int, dict[str, object]] = {}
    sorted_ids = sorted(ids)
    for index, batch in enumerate(batched(sorted_ids, batch_size), start=1):
        digest = hashlib.sha256(",".join(str(value) for value in batch).encode()).hexdigest()[:16]
        path = cache_dir / "taxa" / f"batch-{digest}.json"
        url = f"{TAXA_URL}/{','.join(str(value) for value in batch)}"
        data = read_or_fetch(path, url, refresh=refresh, sleep_seconds=sleep_seconds)
        results = data.get("results") or []
        if not isinstance(results, list):
            raise SystemExit(f"Unexpected taxa response for batch {index}")
        for row in results:
            if isinstance(row, dict) and isinstance(row.get("id"), int):
                taxa[int(row["id"])] = row
        print(f"resolved taxonomy batch {index}/{(len(sorted_ids) + batch_size - 1) // batch_size}")
    missing = ids - taxa.keys()
    if missing:
        raise SystemExit(f"Taxonomy lookup omitted {len(missing)} requested IDs; first={sorted(missing)[:5]}")
    return taxa


def product_taxon(taxonomy: dict[str, str]) -> str:
    class_name = taxonomy.get("class", "")
    phylum = taxonomy.get("phylum", "")
    order = taxonomy.get("order", "")
    if class_name == "Aves":
        return "bird"
    if class_name == "Mammalia":
        return "mammal"
    if class_name == "Reptilia":
        return "reptile"
    if class_name == "Amphibia":
        return "amphibian"
    if class_name == "Actinopterygii":
        return "fish"
    if class_name == "Insecta":
        return "insect"
    if class_name == "Arachnida":
        return "arachnid"
    if phylum == "Mollusca":
        return "mollusk"
    if order == "Decapoda" or class_name in {"Malacostraca", "Branchiopoda"}:
        return "crustacean"
    return "animal"


def catalog_record(
    taxon: dict[str, object], all_taxa: dict[int, dict[str, object]], catalog_version: str
) -> dict[str, object]:
    lineage = [int(value) for value in taxon.get("ancestor_ids") or []]
    if int(taxon["id"]) not in lineage:
        lineage.append(int(taxon["id"]))
    taxonomy = {
        str(all_taxa[taxon_id].get("rank")): str(all_taxa[taxon_id].get("name"))
        for taxon_id in lineage
        if taxon_id in all_taxa and all_taxa[taxon_id].get("rank") in RANKS
    }
    scientific_name = str(taxon["name"])
    common_name = str(taxon.get("preferred_common_name") or scientific_name)
    return {
        "scientificName": scientific_name,
        "commonName": common_name,
        "taxon": product_taxon(taxonomy),
        **{rank: taxonomy.get(rank, "") for rank in RANKS},
        "iNaturalistTaxonID": int(taxon["id"]),
        "regionalResearchObservations": int(taxon["regional_observations_count"]),
        "establishmentMeans": taxon.get("preferred_establishment_means"),
        "sources": [
            {
                "name": "iNaturalist",
                "catalogVersion": catalog_version,
                "taxonID": int(taxon["id"]),
            }
        ],
    }


def write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "\n".join(json.dumps(row, sort_keys=True) for row in rows) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    args = parse_args()
    if args.per_page < 1 or args.per_page > 200:
        raise SystemExit("--per-page must be between 1 and 200")
    if args.taxonomy_batch_size < 1 or args.taxonomy_batch_size > 30:
        raise SystemExit("--taxonomy-batch-size must be between 1 and 30")
    definition = json.loads(args.definition.read_text(encoding="utf-8"))
    species, pages_by_group = load_species_counts(
        definition,
        cache_dir=args.cache_dir,
        per_page=args.per_page,
        max_pages=args.max_pages,
        refresh=args.refresh,
        sleep_seconds=args.sleep_seconds,
    )
    ancestor_taxa_ids = {
        int(taxon_id)
        for taxon in species.values()
        for taxon_id in taxon.get("ancestor_ids") or []
    }
    all_taxa = dict(species)
    all_taxa.update(load_taxa(
        ancestor_taxa_ids - species.keys(),
        cache_dir=args.cache_dir,
        batch_size=args.taxonomy_batch_size,
        refresh=args.refresh,
        sleep_seconds=args.sleep_seconds,
    ))
    rows = sorted(
        (
            catalog_record(taxon, all_taxa, str(definition["catalogVersion"]))
            for taxon in species.values()
        ),
        key=lambda row: str(row["scientificName"]),
    )
    names = [str(row["scientificName"]) for row in rows]
    if len(names) != len(set(names)):
        raise SystemExit("Regional catalog contains duplicate scientific names")
    write_jsonl(args.output, rows)
    report = {
        "catalogVersion": definition["catalogVersion"],
        "cutoffDate": definition["cutoffDate"],
        "placeID": definition["placeID"],
        "speciesCount": len(rows),
        "pagesByIconicTaxon": pages_by_group,
        "productTaxa": dict(Counter(str(row["taxon"]) for row in rows).most_common()),
        "classes": dict(Counter(str(row["class"]) for row in rows).most_common()),
        "orders": dict(Counter(str(row["order"]) for row in rows).most_common(25)),
        "commonNameCoverage": sum(row["commonName"] != row["scientificName"] for row in rows),
        "sourceDefinition": str(args.definition),
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
