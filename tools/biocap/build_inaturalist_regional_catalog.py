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
        help="Optional per-selector page cap for smoke tests.",
    )
    parser.add_argument(
        "--skip-memberships",
        action="store_true",
        help="Skip optional state/area membership queries for a faster catalog smoke test.",
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
    selector_name: str,
    selector_params: dict[str, object],
    place_id: int,
    cutoff_date: str,
    page: int,
    per_page: int,
    require_photos: bool,
    refresh: bool,
    sleep_seconds: float,
) -> dict[str, object]:
    params = {
        "place_id": place_id,
        "quality_grade": "research",
        "verifiable": "true",
        "rank": "species",
        "d2": cutoff_date,
        "page": page,
        "per_page": per_page,
    }
    params.update(selector_params)
    if require_photos:
        params["photos"] = "true"
    url = f"{SPECIES_COUNTS_URL}?{urllib.parse.urlencode(params)}"
    if require_photos:
        scope = f"place-{place_id}-through-{cutoff_date}-photos-per-{per_page}"
    else:
        # Preserve the existing NC cache layout for backward compatibility.
        scope = f"place-{place_id}-through-{cutoff_date}-per-{per_page}"
    path = (
        cache_dir
        / "species-counts"
        / safe_key(scope)
        / f"{safe_key(selector_name)}-page-{page:04d}.json"
    )
    return read_or_fetch(path, url, refresh=refresh, sleep_seconds=sleep_seconds)


def species_selectors(definition: dict[str, object]) -> list[tuple[str, dict[str, object]]]:
    iconic_taxa = definition.get("iconicTaxa")
    if isinstance(iconic_taxa, list) and iconic_taxa:
        return [
            (str(iconic_taxon), {"iconic_taxa": str(iconic_taxon)})
            for iconic_taxon in iconic_taxa
        ]
    taxon_id = definition.get("taxonID")
    if isinstance(taxon_id, int) and taxon_id > 0:
        return [(f"taxon-{taxon_id}", {"taxon_id": taxon_id})]
    raise SystemExit("Catalog definition must provide iconicTaxa or a positive taxonID")


def load_species_counts(
    definition: dict[str, object],
    *,
    cache_dir: Path,
    per_page: int,
    max_pages: int | None,
    refresh: bool,
    sleep_seconds: float,
    place_id: int | None = None,
    place_label: str | None = None,
) -> tuple[dict[int, dict[str, object]], dict[str, int]]:
    records: dict[int, dict[str, object]] = {}
    pages_by_group: dict[str, int] = {}
    resolved_place_id = place_id if place_id is not None else int(definition["placeID"])
    resolved_place_label = place_label or f"place-{resolved_place_id}"
    for selector_name, selector_params in species_selectors(definition):
        page = 1
        group_pages = 0
        while True:
            data = species_count_page(
                cache_dir=cache_dir,
                selector_name=selector_name,
                selector_params=selector_params,
                place_id=resolved_place_id,
                cutoff_date=str(definition["cutoffDate"]),
                page=page,
                per_page=per_page,
                require_photos=bool(definition.get("requirePhotos", False)),
                refresh=refresh,
                sleep_seconds=sleep_seconds,
            )
            group_pages += 1
            results = data.get("results") or []
            if not isinstance(results, list):
                raise SystemExit(
                    f"Unexpected species-count response for {resolved_place_label} "
                    f"{selector_name} page {page}"
                )
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
        pages_by_group[selector_name] = group_pages
        print(
            json.dumps(
                {
                    "place": resolved_place_label,
                    "selector": selector_name,
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
    requested_ids = set(ids)
    taxa_cache_dir = cache_dir / "taxa"
    if not refresh and taxa_cache_dir.exists():
        for path in sorted(taxa_cache_dir.glob("batch-*.json")):
            data = json.loads(path.read_text(encoding="utf-8"))
            for row in data.get("results") or []:
                taxon_id = row.get("id") if isinstance(row, dict) else None
                if isinstance(taxon_id, int) and taxon_id in requested_ids:
                    taxa[taxon_id] = row

    missing_ids = sorted(requested_ids - taxa.keys())
    batches = list(batched(missing_ids, batch_size))
    for index, batch in enumerate(batches, start=1):
        digest = hashlib.sha256(",".join(str(value) for value in batch).encode()).hexdigest()[:16]
        path = taxa_cache_dir / f"batch-{digest}.json"
        url = f"{TAXA_URL}/{','.join(str(value) for value in batch)}"
        data = read_or_fetch(path, url, refresh=refresh, sleep_seconds=sleep_seconds)
        results = data.get("results") or []
        if not isinstance(results, list):
            raise SystemExit(f"Unexpected taxa response for batch {index}")
        for row in results:
            if isinstance(row, dict) and isinstance(row.get("id"), int):
                taxa[int(row["id"])] = row
        print(f"resolved taxonomy batch {index}/{len(batches)}")
    missing = requested_ids - taxa.keys()
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
    taxon: dict[str, object],
    all_taxa: dict[int, dict[str, object]],
    catalog_version: str,
    *,
    observation_count_field: str = "regionalResearchObservations",
    area_observation_counts: dict[str, int] | None = None,
    area_regions: dict[str, str] | None = None,
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
    row: dict[str, object] = {
        "scientificName": scientific_name,
        "commonName": common_name,
        "taxon": product_taxon(taxonomy),
        **{rank: taxonomy.get(rank, "") for rank in RANKS},
        "iNaturalistTaxonID": int(taxon["id"]),
        observation_count_field: int(taxon["regional_observations_count"]),
        "establishmentMeans": taxon.get("preferred_establishment_means"),
        "sources": [
            {
                "name": "iNaturalist",
                "catalogVersion": catalog_version,
                "taxonID": int(taxon["id"]),
            }
        ],
    }
    if area_observation_counts is not None:
        counts = {
            code: int(area_observation_counts[code])
            for code in sorted(area_observation_counts)
        }
        row["areaCodes"] = list(counts)
        row["areaObservationCounts"] = counts
        regions = {
            area_regions[code]
            for code in counts
            if area_regions is not None and code in area_regions
        }
        row["regionIDs"] = sorted(regions)
    synonyms = sorted({str(value) for value in taxon.get("catalog_synonyms") or []})
    if synonyms:
        row["synonyms"] = synonyms
    return row


def validate_membership_definition(
    definition: dict[str, object],
) -> tuple[list[dict[str, object]], dict[str, str]]:
    places_value = definition.get("membershipPlaces") or []
    if not isinstance(places_value, list):
        raise SystemExit("membershipPlaces must be a list")
    places = [dict(place) for place in places_value if isinstance(place, dict)]
    if len(places) != len(places_value):
        raise SystemExit("Every membershipPlaces entry must be an object")

    codes = [str(place.get("code") or "") for place in places]
    place_ids = [place.get("placeID") for place in places]
    if any(not code for code in codes) or len(codes) != len(set(codes)):
        raise SystemExit("membershipPlaces must have unique, non-empty codes")
    if any(not isinstance(place_id, int) or place_id <= 0 for place_id in place_ids):
        raise SystemExit("membershipPlaces must have positive integer placeID values")
    if len(place_ids) != len(set(place_ids)):
        raise SystemExit("membershipPlaces must have unique placeID values")

    regions_value = definition.get("regions") or []
    if not isinstance(regions_value, list):
        raise SystemExit("regions must be a list")
    region_ids = {
        str(region.get("id"))
        for region in regions_value
        if isinstance(region, dict) and region.get("id")
    }
    area_regions: dict[str, str] = {}
    for place in places:
        code = str(place["code"])
        region_id = str(place.get("regionID") or "")
        if not region_id or region_id not in region_ids:
            raise SystemExit(f"Membership place {code} has an unknown regionID {region_id!r}")
        area_regions[code] = region_id
    return places, area_regions


def merge_membership_records(
    species: dict[int, dict[str, object]],
    membership_by_taxon: dict[int, dict[str, int]],
    place_species: dict[int, dict[str, object]],
    area_code: str,
) -> set[int]:
    """Join one area and retain active state taxa missing from the parent query.

    iNaturalist observation dates are frozen by the catalog cutoff, but taxonomy
    can still change while a long paged build is running. The selected state
    union is therefore allowed to contribute a newly active taxon that was not
    present in the earlier United States parent response.
    """
    membership_only_taxa: set[int] = set()
    for taxon_id, taxon in place_species.items():
        if taxon_id not in species:
            species[taxon_id] = dict(taxon)
            membership_only_taxa.add(taxon_id)
        membership_by_taxon.setdefault(taxon_id, {})[area_code] = int(
            taxon["regional_observations_count"]
        )
    return membership_only_taxa


def reconcile_current_species(
    species: dict[int, dict[str, object]],
    membership_by_taxon: dict[int, dict[str, int]],
    current_taxa: dict[int, dict[str, object]],
) -> dict[str, int]:
    inactive_ids = [
        taxon_id
        for taxon_id in sorted(species)
        if not bool(current_taxa[taxon_id].get("is_active", True))
    ]
    replacements = 0
    for taxon_id in inactive_ids:
        stale = species[taxon_id]
        replacement_ids = [
            int(value)
            for value in current_taxa[taxon_id].get("current_synonymous_taxon_ids") or []
        ]
        if len(replacement_ids) != 1:
            raise SystemExit(
                f"Inactive species {taxon_id} has {len(replacement_ids)} current replacements; "
                "a split/merge cannot be reconciled automatically"
            )
        replacement_id = replacement_ids[0]
        if replacement_id not in current_taxa:
            raise SystemExit(
                f"Inactive species {taxon_id} points to unresolved replacement {replacement_id}"
            )
        replacement = species.get(replacement_id)
        if replacement is None:
            replacement = dict(current_taxa[replacement_id])
            replacement["regional_observations_count"] = int(
                stale["regional_observations_count"]
            )
            species[replacement_id] = replacement
        else:
            replacement["regional_observations_count"] = max(
                int(replacement["regional_observations_count"]),
                int(stale["regional_observations_count"]),
            )
        replacement.setdefault("catalog_synonyms", []).append(str(stale["name"]))
        stale_memberships = membership_by_taxon.pop(taxon_id, {})
        replacement_memberships = membership_by_taxon.setdefault(replacement_id, {})
        for code, count in stale_memberships.items():
            replacement_memberships[code] = max(
                replacement_memberships.get(code, 0),
                count,
            )
        del species[taxon_id]
        replacements += 1

    for taxon_id, taxon in list(species.items()):
        current = current_taxa[taxon_id]
        observation_count = int(taxon["regional_observations_count"])
        synonyms = list(taxon.get("catalog_synonyms") or [])
        species[taxon_id] = dict(current)
        species[taxon_id]["regional_observations_count"] = observation_count
        if synonyms:
            species[taxon_id]["catalog_synonyms"] = synonyms
    return {
        "validatedSpeciesIDs": len(current_taxa),
        "inactiveRowsReplaced": replacements,
    }


def write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "\n".join(json.dumps(row, sort_keys=True) for row in rows) + "\n",
        encoding="utf-8",
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    args = parse_args()
    if args.per_page < 1 or args.per_page > 200:
        raise SystemExit("--per-page must be between 1 and 200")
    if args.taxonomy_batch_size < 1 or args.taxonomy_batch_size > 30:
        raise SystemExit("--taxonomy-batch-size must be between 1 and 30")
    definition = json.loads(args.definition.read_text(encoding="utf-8"))
    defined_membership_places, area_regions = validate_membership_definition(definition)
    membership_places = [] if args.skip_memberships else defined_membership_places
    species, pages_by_group = load_species_counts(
        definition,
        cache_dir=args.cache_dir,
        per_page=args.per_page,
        max_pages=args.max_pages,
        refresh=args.refresh,
        sleep_seconds=args.sleep_seconds,
    )
    membership_by_taxon: dict[int, dict[str, int]] = {}
    membership_only_taxa: set[int] = set()
    membership_report: list[dict[str, object]] = []
    for place in membership_places:
        code = str(place["code"])
        place_species, place_pages = load_species_counts(
            definition,
            cache_dir=args.cache_dir,
            per_page=args.per_page,
            max_pages=args.max_pages,
            refresh=args.refresh,
            sleep_seconds=args.sleep_seconds,
            place_id=int(place["placeID"]),
            place_label=code,
        )
        membership_only_taxa.update(
            merge_membership_records(
                species,
                membership_by_taxon,
                place_species,
                code,
            )
        )
        membership_report.append(
            {
                "code": code,
                "name": place.get("name"),
                "placeID": place["placeID"],
                "regionID": place["regionID"],
                "speciesCount": len(place_species),
                "pages": place_pages,
            }
        )
    for taxon_id in membership_only_taxa:
        # The parent response did not contain these newly active rows. The sum
        # of selected state observations is a deterministic lower-bound U.S.
        # count and keeps the source record internally consistent.
        species[taxon_id]["regional_observations_count"] = sum(
            membership_by_taxon[taxon_id].values()
        )
    current_species = load_taxa(
        set(species),
        cache_dir=args.cache_dir / "species-validation",
        batch_size=args.taxonomy_batch_size,
        refresh=args.refresh,
        sleep_seconds=args.sleep_seconds,
    )
    replacement_ids = {
        int(replacement_id)
        for taxon_id, taxon in current_species.items()
        if not bool(taxon.get("is_active", True))
        for replacement_id in taxon.get("current_synonymous_taxon_ids") or []
        if int(replacement_id) not in current_species
    }
    if replacement_ids:
        current_species.update(
            load_taxa(
                replacement_ids,
                cache_dir=args.cache_dir / "species-validation",
                batch_size=args.taxonomy_batch_size,
                refresh=args.refresh,
                sleep_seconds=args.sleep_seconds,
            )
        )
    taxonomy_reconciliation = reconcile_current_species(
        species,
        membership_by_taxon,
        current_species,
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
            catalog_record(
                taxon,
                all_taxa,
                str(definition["catalogVersion"]),
                observation_count_field=str(
                    definition.get("observationCountField")
                    or "regionalResearchObservations"
                ),
                area_observation_counts=(
                    membership_by_taxon.get(int(taxon["id"]), {})
                    if membership_places
                    else None
                ),
                area_regions=area_regions,
            )
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
        "catalogDefinitionSHA256": sha256_file(args.definition),
        "generatedSpeciesJSONLSHA256": sha256_file(args.output),
        "cutoffDate": definition["cutoffDate"],
        "placeID": definition["placeID"],
        "speciesCount": len(rows),
        "uniqueINaturalistTaxonIDs": len(
            {int(row["iNaturalistTaxonID"]) for row in rows}
        ),
        "sourceJSONLBytes": args.output.stat().st_size,
        "estimatedEmbeddingBytes": {
            "float32": len(rows) * 512 * 4,
            "float16": len(rows) * 512 * 2,
            "int8BeforeScales": len(rows) * 512,
        },
        "pagesBySelector": pages_by_group,
        "requirePhotos": bool(definition.get("requirePhotos", False)),
        "productTaxa": dict(Counter(str(row["taxon"]) for row in rows).most_common()),
        "classes": dict(Counter(str(row["class"]) for row in rows).most_common()),
        "orders": dict(Counter(str(row["order"]) for row in rows).most_common(25)),
        "missingCanonicalRanks": {
            rank: sum(not row.get(rank) for row in rows)
            for rank in RANKS
        },
        "commonNameCoverage": sum(row["commonName"] != row["scientificName"] for row in rows),
        "membershipPlaces": membership_report,
        "membershipsSkipped": args.skip_memberships,
        "membershipAssignments": sum(len(row.get("areaCodes") or []) for row in rows),
        "membershipOnlyTaxa": len(membership_only_taxa),
        "taxonomyReconciliation": taxonomy_reconciliation,
        "speciesWithoutMembershipArea": sum(not row.get("areaCodes") for row in rows),
        "regionSpeciesCounts": dict(
            Counter(
                region_id
                for row in rows
                for region_id in row.get("regionIDs") or []
            ).most_common()
        ),
        "sourceDefinition": str(args.definition),
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
