#!/usr/bin/env python3
"""Export validated BioCAP artifacts into local iOS resource files."""

from __future__ import annotations

import argparse
import csv
import json
import shutil
from pathlib import Path

import numpy as np


TAXONOMY_FIELDS = ("kingdom", "phylum", "class", "order", "family", "genus", "species")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--embeddings",
        type=Path,
        required=True,
        help="BioCAP text embeddings .npz from validate_biocap.py.",
    )
    parser.add_argument(
        "--species-list",
        type=Path,
        required=True,
        help="Species JSONL used to generate the embeddings.",
    )
    parser.add_argument(
        "--model",
        type=Path,
        required=True,
        help="Exported BioCAPVisionEncoder.mlpackage.",
    )
    parser.add_argument(
        "--geography-definition",
        type=Path,
        help=(
            "Optional regional catalog definition. When supplied, export one "
            "little-endian UInt64 state-membership mask per species plus the "
            "state-to-region mapping in BioCAPConfig.json."
        ),
    )
    parser.add_argument(
        "--image-manifest",
        type=Path,
        help="Optional validation image manifest used to copy one local fixture.",
    )
    parser.add_argument(
        "--rankings",
        type=Path,
        help="Optional rankings.csv used to choose a fixture that ranked top-1.",
    )
    parser.add_argument(
        "--fixture-scientific-name",
        default="Calypte anna",
        help="Preferred fixture species when present in the manifest.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("Fieldnotes/Fieldnotes/Resources/BioCAP"),
        help="Generated iOS resource directory.",
    )
    return parser.parse_args()


def read_jsonl(path: Path) -> list[dict[str, object]]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def validated_embeddings(
    archive: np.lib.npyio.NpzFile, species_rows: list[dict[str, object]]
) -> np.ndarray:
    if "embeddings" not in archive.files:
        raise SystemExit("Embedding archive has no embeddings array.")
    if "scientific_names" not in archive.files:
        raise SystemExit(
            "Embedding archive has no scientific_names array; row order cannot be verified."
        )
    species_names = [str(row.get("scientificName") or "") for row in species_rows]
    if not all(species_names):
        raise SystemExit("Species list contains a row without scientificName.")
    if len(species_names) != len(set(species_names)):
        raise SystemExit("Species list contains duplicate scientific names.")
    embedded_names = [str(value) for value in archive["scientific_names"].tolist()]
    if embedded_names != species_names:
        mismatch = next(
            (
                index
                for index, (embedded, expected) in enumerate(
                    zip(embedded_names, species_names, strict=False)
                )
                if embedded != expected
            ),
            min(len(embedded_names), len(species_names)),
        )
        embedded = embedded_names[mismatch] if mismatch < len(embedded_names) else "<missing>"
        expected = species_names[mismatch] if mismatch < len(species_names) else "<missing>"
        raise SystemExit(
            f"Embedding/species row-order mismatch at index {mismatch}: "
            f"archive={embedded!r}, species-list={expected!r}"
        )
    embeddings = archive["embeddings"].astype("<f4")
    if embeddings.ndim != 2 or embeddings.shape[0] != len(species_rows):
        raise SystemExit(
            f"Embedding shape {embeddings.shape} does not match {len(species_rows)} species."
        )
    if not np.isfinite(embeddings).all():
        raise SystemExit("Embedding matrix contains non-finite values.")
    norms = np.linalg.norm(embeddings, axis=1)
    if np.any(norms <= 0) or not np.allclose(norms, 1.0, atol=0.005):
        raise SystemExit("Embedding rows must be finite and unit-normalized within 0.005.")
    return embeddings


def build_geography_export(
    species_rows: list[dict[str, object]], definition: dict[str, object]
) -> tuple[dict[str, object], np.ndarray]:
    regions = definition.get("regions")
    places = definition.get("membershipPlaces")
    if not isinstance(regions, list) or not regions:
        raise SystemExit("Geography definition must contain a non-empty regions list.")
    if not isinstance(places, list) or not places:
        raise SystemExit(
            "Geography definition must contain a non-empty membershipPlaces list."
        )
    if len(places) > 64:
        raise SystemExit("Geography export supports at most 64 membership places.")

    region_records: list[dict[str, str]] = []
    region_indices: dict[str, int] = {}
    for index, value in enumerate(regions):
        if not isinstance(value, dict):
            raise SystemExit("Every geography region must be an object.")
        region_id = str(value.get("id") or "")
        display_name = str(value.get("displayName") or "")
        if not region_id or not display_name or region_id in region_indices:
            raise SystemExit("Geography regions require unique IDs and display names.")
        region_indices[region_id] = index
        region_records.append({"id": region_id, "displayName": display_name})

    state_codes: list[str] = []
    state_display_names: list[str] = []
    state_region_indices: list[int] = []
    state_indices: dict[str, int] = {}
    for index, value in enumerate(places):
        if not isinstance(value, dict):
            raise SystemExit("Every geography membership place must be an object.")
        code = str(value.get("code") or "")
        display_name = str(value.get("name") or "")
        region_id = str(value.get("regionID") or "")
        if not code or not display_name or code in state_indices:
            raise SystemExit(
                "Geography membership places require unique codes and display names."
            )
        if region_id not in region_indices:
            raise SystemExit(
                f"Geography membership place {code!r} has unknown region {region_id!r}."
            )
        state_indices[code] = index
        state_codes.append(code)
        state_display_names.append(display_name)
        state_region_indices.append(region_indices[region_id])

    masks = np.zeros(len(species_rows), dtype="<u8")
    for row_index, row in enumerate(species_rows):
        area_codes = row.get("areaCodes")
        region_ids = row.get("regionIDs")
        if not isinstance(area_codes, list) or not area_codes:
            raise SystemExit(
                f"Species row {row_index} has no geography areaCodes membership."
            )
        unknown_codes = sorted({str(code) for code in area_codes} - set(state_indices))
        if unknown_codes:
            raise SystemExit(
                f"Species row {row_index} has unknown geography codes: {unknown_codes}."
            )
        expected_regions = {
            region_records[state_region_indices[state_indices[str(code)]]]["id"]
            for code in area_codes
        }
        actual_regions = (
            {str(region_id) for region_id in region_ids}
            if isinstance(region_ids, list)
            else set()
        )
        if actual_regions != expected_regions:
            raise SystemExit(
                f"Species row {row_index} regionIDs do not match its areaCodes."
            )
        mask = 0
        for code in area_codes:
            mask |= 1 << state_indices[str(code)]
        masks[row_index] = mask

    return (
        {
            "stateCodes": state_codes,
            "stateDisplayNames": state_display_names,
            "stateRegionIndices": state_region_indices,
            "regions": region_records,
        },
        masks,
    )


def read_ranked_top1(path: Path) -> set[str]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = csv.DictReader(handle)
        return {
            row["image"]
            for row in rows
            if row.get("expectedScientificName") == row.get("fullTop1")
        }


def choose_fixture(
    manifest_path: Path | None,
    rankings_path: Path | None,
    preferred_scientific_name: str,
) -> dict[str, object] | None:
    if manifest_path is None:
        return None

    rows = read_jsonl(manifest_path)
    for row in rows:
        fixture_path = Path(str(row["path"]))
        if not fixture_path.is_absolute() and not fixture_path.is_file():
            row["path"] = str(manifest_path.parent / fixture_path)
    top1_images = read_ranked_top1(rankings_path) if rankings_path else set()

    def is_top1(row: dict[str, object]) -> bool:
        return not top1_images or str(Path(str(row["path"])).resolve()) in top1_images

    for row in rows:
        if row.get("expectedScientificName") == preferred_scientific_name and is_top1(row):
            return row

    for row in rows:
        if is_top1(row):
            return row

    return rows[0] if rows else None


def main() -> None:
    args = parse_args()
    output_dir = args.output_dir
    model_dir = output_dir / "Models"
    fixture_dir = output_dir / "TestFixtures"
    model_dir.mkdir(parents=True, exist_ok=True)
    fixture_dir.mkdir(parents=True, exist_ok=True)

    embeddings_npz = np.load(args.embeddings)
    species_rows = read_jsonl(args.species_list)
    embeddings = validated_embeddings(embeddings_npz, species_rows)
    embeddings_path = output_dir / "BioCAPTextEmbeddings.f32"
    embeddings.tofile(embeddings_path)

    geography_config = None
    geography_path = None
    if args.geography_definition is not None:
        definition = json.loads(args.geography_definition.read_text(encoding="utf-8"))
        geography_config, geography_masks = build_geography_export(
            species_rows, definition
        )
        geography_path = output_dir / "BioCAPGeography.bin"
        geography_masks.tofile(geography_path)

    metadata = []
    for index, row in enumerate(species_rows):
        output_row = {
            "index": index,
            "scientificName": row["scientificName"],
            "commonName": row.get("commonName") or row["scientificName"],
            "taxon": row.get("taxon") or "unknown",
        }
        for key in (
            *TAXONOMY_FIELDS,
            "synonyms",
            "sources",
            "iNaturalistTaxonID",
            "regionalResearchObservations",
            "establishmentMeans",
            "catalogTier",
            "alsoInTravelFallback",
            "fallbackSources",
        ):
            if row.get(key) not in (None, "", []):
                output_row[key] = row[key]
        metadata.append(output_row)
    (output_dir / "BioCAPSpecies.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True),
        encoding="utf-8",
    )

    prompt_templates = embeddings_npz.get("prompt_templates", np.asarray([]))
    config = {
        "embeddingDim": int(embeddings.shape[1]),
        "speciesCount": int(embeddings.shape[0]),
        "embeddingDtype": "float32",
        "modelName": str(embeddings_npz.get("model_name", np.asarray([""]))[0]),
        "promptPreset": str(embeddings_npz.get("prompt_preset", np.asarray([""]))[0]),
        "labelTextType": str(embeddings_npz.get("label_text_type", np.asarray([""]))[0]),
        "promptTemplateCount": int(len(prompt_templates)),
    }
    if geography_config is not None:
        config["geography"] = geography_config
    (output_dir / "BioCAPConfig.json").write_text(
        json.dumps(config, indent=2, sort_keys=True),
        encoding="utf-8",
    )

    destination_model = model_dir / args.model.name
    if destination_model.exists():
        shutil.rmtree(destination_model)
    shutil.copytree(args.model, destination_model)

    fixture = choose_fixture(
        args.image_manifest,
        args.rankings,
        args.fixture_scientific_name,
    )
    if fixture is not None:
        fixture_source = Path(str(fixture["path"]))
        fixture_destination = fixture_dir / "BioCAPFixture.jpg"
        shutil.copy2(fixture_source, fixture_destination)
        (fixture_dir / "BioCAPFixture.json").write_text(
            json.dumps(
                {
                    "expectedScientificName": fixture["expectedScientificName"],
                    "sourcePath": str(fixture_source),
                    "sourceURL": fixture.get("sourceURL"),
                },
                indent=2,
                sort_keys=True,
            ),
            encoding="utf-8",
        )

    print(
        json.dumps(
            {
                "outputDir": str(output_dir),
                "model": str(destination_model),
                "embeddings": str(embeddings_path),
                "speciesCount": config["speciesCount"],
                "embeddingDim": config["embeddingDim"],
                "geography": str(geography_path) if geography_path else None,
                "fixture": str((fixture_dir / "BioCAPFixture.jpg")) if fixture else None,
            },
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
