#!/usr/bin/env python3
"""Prepare a reproducible, licensed North Carolina BioCAP evaluation set."""

from __future__ import annotations

import argparse
import json
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path


OBSERVATIONS_URL = "https://api.inaturalist.org/v1/observations"
TAXA_URL = "https://api.inaturalist.org/v1/taxa"
DATASET_PAGE = "https://www.inaturalist.org"
ALLOWED_LICENSES = {
    "cc0",
    "cc-by",
    "cc-by-sa",
    "cc-by-nc",
    "cc-by-nc-sa",
}
USER_AGENT = "Fieldnotes-BioCAP-NC-evaluation/1.0"


@dataclass(frozen=True)
class Region:
    key: str
    display_name: str
    swlat: float
    swlng: float
    nelat: float
    nelng: float


@dataclass(frozen=True)
class PhotoSelection:
    observation_id: int
    photo_id: int


@dataclass(frozen=True)
class TargetTaxon:
    scientific_name: str
    group: str
    region: Region
    selections: tuple[PhotoSelection, ...]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--definition",
        type=Path,
        default=Path("tools/biocap/evaluation/nc-v1.json"),
        help="Versioned dataset definition.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("tmp/biocap-datasets/nc-v1"),
        help="Ignored local image and manifest directory.",
    )
    parser.add_argument(
        "--images-per-taxon",
        type=int,
        help="Override the definition's image count for a smoke run.",
    )
    parser.add_argument(
        "--max-taxa",
        type=int,
        default=0,
        help="Optional target cap for a smoke run.",
    )
    parser.add_argument(
        "--sleep-seconds",
        type=float,
        default=1.0,
        help="Delay between API requests, respecting iNaturalist guidance.",
    )
    parser.add_argument(
        "--accept-terms",
        action="store_true",
        help="Required. Confirms local validation use and attribution retention.",
    )
    return parser.parse_args()


def get_json(url: str) -> dict[str, object]:
    request = urllib.request.Request(
        url,
        headers={"Accept": "application/json", "User-Agent": USER_AGENT},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def download(url: str, destination: Path) -> bool:
    if destination.exists() and destination.stat().st_size > 0:
        return False
    destination.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response, destination.open("wb") as handle:
        while chunk := response.read(1024 * 1024):
            handle.write(chunk)
    return True


def safe_stem(value: str) -> str:
    return "".join(
        character.lower() if character.isalnum() else "-" for character in value
    ).strip("-")


def load_definition(
    path: Path, max_taxa: int
) -> tuple[dict[str, object], list[TargetTaxon]]:
    definition = json.loads(path.read_text(encoding="utf-8"))
    regions = {
        key: Region(
            key=key,
            display_name=row["displayName"],
            swlat=float(row["swlat"]),
            swlng=float(row["swlng"]),
            nelat=float(row["nelat"]),
            nelng=float(row["nelng"]),
        )
        for key, row in definition["regions"].items()
    }
    targets = []
    seen_names = set()
    for row in definition["taxa"]:
        name = str(row["scientificName"]).strip()
        if name in seen_names:
            raise SystemExit(f"Duplicate target scientific name: {name}")
        seen_names.add(name)
        region_key = str(row["region"])
        if region_key not in regions:
            raise SystemExit(f"Unknown region {region_key} for {name}")
        targets.append(
            TargetTaxon(
                scientific_name=name,
                group=str(row["group"]),
                region=regions[region_key],
                selections=tuple(
                    PhotoSelection(
                        observation_id=int(selection["observationID"]),
                        photo_id=int(selection["photoID"]),
                    )
                    for selection in row.get("selections") or []
                ),
            )
        )
    if max_taxa > 0:
        targets = targets[:max_taxa]
    required_groups = set(definition.get("requiredGroups") or [])
    available_groups = {target.group for target in targets}
    if max_taxa == 0 and required_groups != available_groups:
        missing = sorted(required_groups - available_groups)
        extra = sorted(available_groups - required_groups)
        raise SystemExit(f"Group coverage mismatch; missing={missing}, extra={extra}")
    return definition, targets


def query_observations(
    target: TargetTaxon,
    *,
    place_id: int,
    cutoff_date: str,
    limit: int,
) -> list[dict[str, object]]:
    if target.selections:
        ids = [selection.observation_id for selection in target.selections[:limit]]
        params = {"id": ",".join(str(value) for value in ids), "per_page": len(ids)}
        return list(
            get_json(f"{OBSERVATIONS_URL}?{urllib.parse.urlencode(params)}").get("results")
            or []
        )
    params = {
        "taxon_name": target.scientific_name,
        "quality_grade": "research",
        "photos": "true",
        "rank": "species",
        "place_id": place_id,
        "swlat": target.region.swlat,
        "swlng": target.region.swlng,
        "nelat": target.region.nelat,
        "nelng": target.region.nelng,
        "d2": cutoff_date,
        "order_by": "votes",
        "order": "desc",
        "per_page": min(200, max(40, limit * 20)),
        "page": 1,
    }
    return list(get_json(f"{OBSERVATIONS_URL}?{urllib.parse.urlencode(params)}").get("results") or [])


def best_photo(
    observation: dict[str, object], photo_id: int | None = None
) -> dict[str, object] | None:
    for photo in observation.get("photos") or []:
        if photo_id is not None and int(photo.get("id") or 0) != photo_id:
            continue
        if photo.get("license_code") in ALLOWED_LICENSES and photo.get("url"):
            return photo
    return None


def medium_photo_url(photo: dict[str, object]) -> str:
    if photo.get("medium_url"):
        return str(photo["medium_url"])
    return str(photo["url"]).replace("square.", "medium.").replace("small.", "medium.")


def resolve_taxonomy(taxon: dict[str, object]) -> dict[str, str]:
    ids = [int(value) for value in taxon.get("ancestor_ids") or []]
    if int(taxon["id"]) not in ids:
        ids.append(int(taxon["id"]))
    data = get_json(f"{TAXA_URL}/{','.join(str(value) for value in ids)}")
    by_rank = {
        str(row.get("rank")): str(row.get("name"))
        for row in data.get("results") or []
        if row.get("rank") and row.get("name")
    }
    return {
        "expectedKingdom": by_rank.get("kingdom", ""),
        "expectedPhylum": by_rank.get("phylum", ""),
        "expectedClass": by_rank.get("class", ""),
        "expectedOrder": by_rank.get("order", ""),
        "expectedFamily": by_rank.get("family", ""),
        "expectedGenus": by_rank.get("genus", ""),
    }


def write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    text = "\n".join(json.dumps(row, sort_keys=True) for row in rows)
    path.write_text(text + ("\n" if text else ""), encoding="utf-8")


def main() -> None:
    args = parse_args()
    if not args.accept_terms:
        raise SystemExit(
            "Pass --accept-terms after reviewing iNaturalist terms and licensing at "
            f"{DATASET_PAGE}. Use locally for validation and retain attribution."
        )

    definition, targets = load_definition(args.definition, args.max_taxa)
    dataset_version = str(definition["datasetVersion"])
    cutoff_date = str(definition["cutoffDate"])
    place_id = int(definition["iNaturalistPlaceID"])
    images_per_taxon = args.images_per_taxon or int(definition["imagesPerTaxon"])
    if images_per_taxon <= 0:
        raise SystemExit("images-per-taxon must be positive")

    root = args.output_dir
    root.mkdir(parents=True, exist_ok=True)
    manifest_rows: list[dict[str, object]] = []
    attribution_rows: list[dict[str, object]] = []
    shortfalls: list[dict[str, object]] = []

    for target in targets:
        print(f"querying {target.scientific_name} in {target.region.key}")
        observations = query_observations(
            target,
            place_id=place_id,
            cutoff_date=cutoff_date,
            limit=images_per_taxon,
        )
        time.sleep(args.sleep_seconds)
        selected = []
        observations_by_id = {int(row["id"]): row for row in observations}
        requested_selections = target.selections[:images_per_taxon]
        if requested_selections:
            for selection in requested_selections:
                observation = observations_by_id.get(selection.observation_id)
                if observation is None:
                    continue
                taxon = observation.get("taxon") or {}
                if taxon.get("name") != target.scientific_name:
                    continue
                photo = best_photo(observation, selection.photo_id)
                if photo is not None:
                    selected.append((observation, photo))
        else:
            for observation in observations:
                taxon = observation.get("taxon") or {}
                if taxon.get("name") != target.scientific_name:
                    continue
                photo = best_photo(observation)
                if photo is None:
                    continue
                selected.append((observation, photo))
                if len(selected) >= images_per_taxon:
                    break

        if len(selected) < images_per_taxon:
            shortfalls.append(
                {
                    "scientificName": target.scientific_name,
                    "requested": images_per_taxon,
                    "selected": len(selected),
                }
            )
        if not selected:
            continue

        taxonomy = resolve_taxonomy(selected[0][0]["taxon"])
        time.sleep(args.sleep_seconds)
        stem = safe_stem(target.scientific_name)
        for observation, photo in selected:
            observation_id = int(observation["id"])
            photo_id = int(photo["id"])
            relative_path = Path("images") / stem / f"{stem}-{observation_id}-{photo_id}.jpg"
            photo_url = medium_photo_url(photo)
            if download(photo_url, root / relative_path):
                time.sleep(args.sleep_seconds)

            observation_url = observation.get("uri") or (
                f"https://www.inaturalist.org/observations/{observation_id}"
            )
            common_name = (observation.get("taxon") or {}).get("preferred_common_name")
            row = {
                "datasetVersion": dataset_version,
                "imageID": f"{dataset_version}:{observation_id}:{photo_id}",
                "path": str(relative_path),
                "expectedScientificName": target.scientific_name,
                "expectedCommonName": common_name or target.scientific_name,
                "evaluationGroup": target.group,
                "region": target.region.key,
                "regionDisplayName": target.region.display_name,
                "caseTags": ["natural-field-photo", "licensed-inaturalist"],
                "observedOn": observation.get("observed_on"),
                "sourceURL": observation_url,
                **taxonomy,
            }
            manifest_rows.append(row)
            attribution_rows.append(
                {
                    "imageID": row["imageID"],
                    "path": str(relative_path),
                    "scientificName": target.scientific_name,
                    "observationID": observation_id,
                    "observationURL": observation_url,
                    "photoID": photo_id,
                    "photoURL": photo_url,
                    "license": photo.get("license_code"),
                    "attribution": photo.get("attribution"),
                }
            )

    write_jsonl(root / "benchmark_manifest.jsonl", manifest_rows)
    write_jsonl(root / "attribution.jsonl", attribution_rows)
    report = {
        "datasetVersion": dataset_version,
        "definition": str(args.definition),
        "cutoffDate": cutoff_date,
        "targetTaxa": len(targets),
        "imagesPerTaxon": images_per_taxon,
        "images": len(manifest_rows),
        "groups": sorted({row["evaluationGroup"] for row in manifest_rows}),
        "regions": sorted({row["region"] for row in manifest_rows}),
        "shortfalls": shortfalls,
    }
    (root / "dataset_report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
