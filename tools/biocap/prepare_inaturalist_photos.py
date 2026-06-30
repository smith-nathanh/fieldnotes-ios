#!/usr/bin/env python3
"""Build a small labeled field-photo validation set from iNaturalist."""

from __future__ import annotations

import argparse
import json
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path


API_URL = "https://api.inaturalist.org/v1/observations"
DATASET_PAGE = "https://www.inaturalist.org"
ALLOWED_LICENSES = {
    "cc0",
    "cc-by",
    "cc-by-sa",
    "cc-by-nc",
    "cc-by-nc-sa",
}


DEFAULT_TAXA = [
    ("Calypte anna", "bird"),
    ("Buteo lineatus", "bird"),
    ("Corvus brachyrhynchos", "bird"),
    ("Cardinalis cardinalis", "bird"),
    ("Turdus migratorius", "bird"),
    ("Odocoileus virginianus", "mammal"),
    ("Sciurus carolinensis", "mammal"),
    ("Sylvilagus floridanus", "mammal"),
    ("Pseudacris regilla", "amphibian"),
    ("Lithobates catesbeianus", "amphibian"),
    ("Ambystoma maculatum", "amphibian"),
    ("Thamnophis sirtalis", "reptile"),
    ("Anolis carolinensis", "reptile"),
    ("Terrapene carolina", "reptile"),
    ("Danaus plexippus", "insect"),
    ("Apis mellifera", "insect"),
    ("Harmonia axyridis", "insect"),
    ("Tenodera sinensis", "insect"),
    ("Taraxacum officinale", "plant"),
    ("Acer rubrum", "plant"),
    ("Trifolium repens", "plant"),
    ("Trametes versicolor", "fungi"),
    ("Amanita muscaria", "fungi"),
    ("Pleurotus ostreatus", "fungi"),
]


@dataclass(frozen=True)
class TaxonRequest:
    scientific_name: str
    taxon: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("tmp/biocap-datasets/inaturalist-field-photos"),
        help="Local output directory.",
    )
    parser.add_argument(
        "--taxa",
        type=Path,
        help="Optional JSONL taxa file with scientificName and taxon fields.",
    )
    parser.add_argument(
        "--images-per-taxon",
        type=int,
        default=3,
        help="Images to download per taxon.",
    )
    parser.add_argument(
        "--max-taxa",
        type=int,
        default=0,
        help="Optional cap on taxa from the selected taxa list.",
    )
    parser.add_argument(
        "--sleep-seconds",
        type=float,
        default=0.4,
        help="Delay between API calls/downloads.",
    )
    parser.add_argument(
        "--accept-terms",
        action="store_true",
        help="Required. Confirms local validation use and attribution retention.",
    )
    return parser.parse_args()


def load_taxa(path: Path | None, max_taxa: int) -> list[TaxonRequest]:
    if path is None:
        taxa = [TaxonRequest(scientific_name=name, taxon=taxon) for name, taxon in DEFAULT_TAXA]
    else:
        taxa = []
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            row = json.loads(line)
            taxa.append(
                TaxonRequest(
                    scientific_name=row["scientificName"],
                    taxon=row.get("taxon") or "unknown",
                )
            )
    if max_taxa > 0:
        taxa = taxa[:max_taxa]
    return taxa


def get_json(url: str) -> dict[str, object]:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": "Fieldnotes-BioCAP-validation/0.1",
        },
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def download(url: str, destination: Path) -> None:
    if destination.exists() and destination.stat().st_size > 0:
        return
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "Fieldnotes-BioCAP-validation/0.1"},
    )
    with urllib.request.urlopen(request, timeout=60) as response, destination.open("wb") as handle:
        handle.write(response.read())


def medium_photo_url(url: str) -> str:
    return url.replace("square.", "medium.").replace("small.", "medium.")


def query_observations(scientific_name: str, limit: int) -> list[dict[str, object]]:
    params = {
        "taxon_name": scientific_name,
        "quality_grade": "research",
        "photos": "true",
        "rank": "species",
        "order_by": "observed_on",
        "order": "desc",
        "per_page": min(200, max(20, limit * 6)),
        "page": 1,
    }
    url = f"{API_URL}?{urllib.parse.urlencode(params)}"
    data = get_json(url)
    return list(data.get("results") or [])


def best_photo(observation: dict[str, object]) -> dict[str, object] | None:
    for photo in observation.get("photos") or []:
        if photo.get("license_code") in ALLOWED_LICENSES and photo.get("url"):
            return photo
    return None


def safe_stem(value: str) -> str:
    return "".join(
        character.lower() if character.isalnum() else "-"
        for character in value
    ).strip("-")


def main() -> None:
    args = parse_args()
    if not args.accept_terms:
        raise SystemExit(
            "Pass --accept-terms after reviewing iNaturalist terms/licensing at "
            f"{DATASET_PAGE}. Use locally for validation and keep attribution."
        )

    root = args.output_dir
    image_dir = root / "images"
    image_dir.mkdir(parents=True, exist_ok=True)

    taxa = load_taxa(args.taxa, args.max_taxa)
    species_rows = []
    manifest_rows = []
    attribution_rows = []

    for taxon_request in taxa:
        print(f"querying {taxon_request.scientific_name}")
        observations = query_observations(
            taxon_request.scientific_name,
            args.images_per_taxon,
        )
        selected = []
        seen_observations = set()
        for observation in observations:
            observation_id = observation.get("id")
            if observation_id in seen_observations:
                continue
            photo = best_photo(observation)
            if photo is None:
                continue
            selected.append((observation, photo))
            seen_observations.add(observation_id)
            if len(selected) >= args.images_per_taxon:
                break

        if not selected:
            print(f"warning: no usable licensed photos for {taxon_request.scientific_name}")
            continue

        species_rows.append(
            {
                "scientificName": taxon_request.scientific_name,
                "commonName": taxon_request.scientific_name,
                "taxon": taxon_request.taxon,
                "source": "iNaturalist",
            }
        )

        taxon_dir = image_dir / safe_stem(taxon_request.scientific_name)
        taxon_dir.mkdir(parents=True, exist_ok=True)

        for index, (observation, photo) in enumerate(selected, start=1):
            photo_url = medium_photo_url(str(photo["url"]))
            image_path = taxon_dir / f"{safe_stem(taxon_request.scientific_name)}-{index:02d}.jpg"
            download(photo_url, image_path)
            time.sleep(args.sleep_seconds)

            observation_url = observation.get("uri") or f"https://www.inaturalist.org/observations/{observation.get('id')}"
            manifest_rows.append(
                {
                    "path": str(image_path.resolve()),
                    "expectedScientificName": taxon_request.scientific_name,
                    "taxon": taxon_request.taxon,
                    "sourceURL": observation_url,
                }
            )
            attribution_rows.append(
                {
                    "path": str(image_path.resolve()),
                    "scientificName": taxon_request.scientific_name,
                    "observationURL": observation_url,
                    "photoURL": photo_url,
                    "license": photo.get("license_code"),
                    "attribution": photo.get("attribution"),
                }
            )
        time.sleep(args.sleep_seconds)

    species_path = root / "inat_species.jsonl"
    manifest_path = root / "inat_image_manifest.jsonl"
    attribution_path = root / "inat_attribution.jsonl"
    species_path.write_text(
        "\n".join(json.dumps(row, sort_keys=True) for row in species_rows) + "\n",
        encoding="utf-8",
    )
    manifest_path.write_text(
        "\n".join(json.dumps(row, sort_keys=True) for row in manifest_rows) + "\n",
        encoding="utf-8",
    )
    attribution_path.write_text(
        "\n".join(json.dumps(row, sort_keys=True) for row in attribution_rows) + "\n",
        encoding="utf-8",
    )

    print(
        json.dumps(
            {
                "datasetPage": DATASET_PAGE,
                "taxa": len(species_rows),
                "images": len(manifest_rows),
                "speciesList": str(species_path),
                "imageManifest": str(manifest_path),
                "attribution": str(attribution_path),
            },
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
