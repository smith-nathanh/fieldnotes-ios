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
                "fixture": str((fixture_dir / "BioCAPFixture.jpg")) if fixture else None,
            },
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
