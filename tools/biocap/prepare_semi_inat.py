#!/usr/bin/env python3
"""Download and prepare Semi-iNat 2021 validation data for BioCAP testing."""

from __future__ import annotations

import argparse
import json
import random
import tarfile
import urllib.request
from dataclasses import dataclass
from pathlib import Path


DATASET_PAGE = "https://github.com/cvl-umass/semi-inat-2021"
ANNOTATION_URL = "https://vis-www.cs.umass.edu/semi-inat-2021/annotation_v2.json"
VAL_URL = "https://vis-www.cs.umass.edu/semi-inat-2021/val.tar.gz"


@dataclass(frozen=True)
class Taxon:
    class_id: int
    scientific_name: str
    taxon: str
    kingdom: str
    phylum: str
    class_name: str
    order: str
    family: str
    genus: str
    species: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("tmp/biocap-datasets/semi-inat-2021"),
        help="Local dataset/output directory.",
    )
    parser.add_argument(
        "--images-per-class",
        type=int,
        default=0,
        help="Optional image cap per class. 0 keeps all validation images.",
    )
    parser.add_argument(
        "--max-classes",
        type=int,
        default=0,
        help="Optional class cap for quick smoke tests. 0 keeps all classes.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=17,
        help="Sampling seed for class/image caps.",
    )
    parser.add_argument(
        "--accept-terms",
        action="store_true",
        help="Required. Confirms local research/educational use under dataset terms.",
    )
    return parser.parse_args()


def download(url: str, destination: Path) -> None:
    if destination.exists():
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    print(f"downloading {url} -> {destination}")
    with urllib.request.urlopen(url) as response, destination.open("wb") as handle:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            handle.write(chunk)


def extract_archive(archive: Path, destination: Path) -> None:
    val_dir = destination / "val"
    if val_dir.exists() and any(val_dir.iterdir()):
        return
    print(f"extracting {archive} -> {destination}")
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar.getmembers():
            target = (destination / member.name).resolve()
            if not str(target).startswith(str(destination.resolve())):
                raise RuntimeError(f"Unsafe tar member path: {member.name}")
        tar.extractall(destination)


def taxon_bucket(kingdom: str, class_name: str, phylum: str) -> str:
    class_lower = class_name.lower()
    phylum_lower = phylum.lower()
    if class_lower == "aves":
        return "bird"
    if class_lower == "mammalia":
        return "mammal"
    if class_lower == "amphibia":
        return "amphibian"
    if class_lower in {"reptilia", "squamata"}:
        return "reptile"
    if class_lower == "insecta" or phylum_lower == "arthropoda":
        return "insect"
    if kingdom.lower() == "plantae":
        return "plant"
    if kingdom.lower() == "fungi":
        return "fungi"
    return "unknown"


def scientific_name(record: dict[str, object]) -> str:
    genus = str(record.get("genus") or "").strip()
    species = str(record.get("species") or "").strip()
    if species.startswith(genus + " "):
        return species
    return f"{genus} {species}".strip()


def load_taxa(annotation_path: Path) -> dict[int, Taxon]:
    data = json.loads(annotation_path.read_text(encoding="utf-8"))
    taxa = {}
    for record in data["annotations"]:
        class_id = int(record["class_id"])
        kingdom = str(record.get("kingdom") or "")
        phylum = str(record.get("phylum") or "")
        class_name = str(record.get("class") or "")
        name = scientific_name(record)
        taxa[class_id] = Taxon(
            class_id=class_id,
            scientific_name=name,
            taxon=taxon_bucket(kingdom, class_name, phylum),
            kingdom=kingdom,
            phylum=phylum,
            class_name=class_name,
            order=str(record.get("order") or ""),
            family=str(record.get("family") or ""),
            genus=str(record.get("genus") or ""),
            species=str(record.get("species") or ""),
        )
    return taxa


def image_files_for_class(val_dir: Path, class_id: int) -> list[Path]:
    class_dir = val_dir / str(class_id)
    if not class_dir.exists():
        return []
    return sorted(
        path
        for path in class_dir.iterdir()
        if path.suffix.lower() in {".jpg", ".jpeg", ".png"}
    )


def main() -> None:
    args = parse_args()
    if not args.accept_terms:
        raise SystemExit(
            "Pass --accept-terms after reviewing the Semi-iNat terms at "
            f"{DATASET_PAGE}. Use locally for research/evaluation only."
        )

    root = args.output_dir
    annotation_path = root / "annotation_v2.json"
    archive_path = root / "val.tar.gz"
    download(ANNOTATION_URL, annotation_path)
    download(VAL_URL, archive_path)
    extract_archive(archive_path, root)

    taxa = load_taxa(annotation_path)
    rng = random.Random(args.seed)
    class_ids = sorted(taxa)
    if args.max_classes > 0:
        class_ids = sorted(rng.sample(class_ids, min(args.max_classes, len(class_ids))))

    species_rows = []
    manifest_rows = []
    val_dir = root / "val"
    for class_id in class_ids:
        taxon = taxa[class_id]
        image_paths = image_files_for_class(val_dir, class_id)
        if args.images_per_class > 0:
            image_paths = sorted(
                rng.sample(image_paths, min(args.images_per_class, len(image_paths)))
            )
        if not image_paths:
            continue

        species_rows.append(
            {
                "classID": taxon.class_id,
                "scientificName": taxon.scientific_name,
                "commonName": taxon.scientific_name,
                "taxon": taxon.taxon,
                "kingdom": taxon.kingdom,
                "phylum": taxon.phylum,
                "class": taxon.class_name,
                "order": taxon.order,
                "family": taxon.family,
                "genus": taxon.genus,
                "species": taxon.species,
            }
        )
        for image_path in image_paths:
            manifest_rows.append(
                {
                    "path": str(image_path.resolve()),
                    "expectedScientificName": taxon.scientific_name,
                    "classID": taxon.class_id,
                    "taxon": taxon.taxon,
                }
            )

    species_path = root / "semi_inat_species.jsonl"
    manifest_path = root / "semi_inat_val_manifest.jsonl"
    species_path.write_text(
        "\n".join(json.dumps(row, sort_keys=True) for row in species_rows) + "\n",
        encoding="utf-8",
    )
    manifest_path.write_text(
        "\n".join(json.dumps(row, sort_keys=True) for row in manifest_rows) + "\n",
        encoding="utf-8",
    )

    print(
        json.dumps(
            {
                "datasetPage": DATASET_PAGE,
                "classes": len(species_rows),
                "images": len(manifest_rows),
                "speciesList": str(species_path),
                "imageManifest": str(manifest_path),
            },
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
