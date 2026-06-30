#!/usr/bin/env python3
"""Export validated BioCAP artifacts into local iOS resource files."""

from __future__ import annotations

import argparse
import csv
import json
import shutil
from pathlib import Path

import numpy as np


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
    embeddings = embeddings_npz["embeddings"].astype("<f4")
    embeddings_path = output_dir / "BioCAPTextEmbeddings.f32"
    embeddings.tofile(embeddings_path)

    species_rows = read_jsonl(args.species_list)
    metadata = []
    for index, row in enumerate(species_rows):
        metadata.append(
            {
                "index": index,
                "scientificName": row["scientificName"],
                "commonName": row.get("commonName") or row["scientificName"],
                "taxon": row.get("taxon") or "unknown",
            }
        )
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
