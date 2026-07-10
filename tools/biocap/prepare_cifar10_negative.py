#!/usr/bin/env python3
"""Prepare a deterministic low-resolution non-animal control set from CIFAR-10."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from torchvision.datasets import CIFAR10


TARGET_CLASSES = ("airplane", "automobile", "ship", "truck")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--accept-terms", action="store_true")
    parser.add_argument("--images-per-class", type=int, default=10)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("tmp/biocap-datasets/cifar10-negative-v1"),
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not args.accept_terms:
        raise SystemExit("Review the CIFAR-10 source/terms, then pass --accept-terms.")
    if args.images_per_class < 1:
        raise SystemExit("--images-per-class must be positive")
    download_root = args.output_dir / "download"
    dataset = CIFAR10(root=download_root, train=False, download=True)
    target_ids = {dataset.class_to_idx[name]: name for name in TARGET_CLASSES}
    selected: dict[str, list[int]] = {name: [] for name in TARGET_CLASSES}
    manifest = []
    image_dir = args.output_dir / "images"
    image_dir.mkdir(parents=True, exist_ok=True)
    for index, (image, class_id) in enumerate(dataset):
        class_name = target_ids.get(class_id)
        if class_name is None or len(selected[class_name]) >= args.images_per_class:
            continue
        selected[class_name].append(index)
        path = image_dir / f"{class_name}-{index}.png"
        image.save(path)
        manifest.append(
            {
                "imageID": f"cifar10:test:{index}",
                "path": str(path.resolve()),
                "datasetVersion": "cifar10-negative-v1",
                "expectedScientificName": "",
                "evaluationGroup": f"negative-{class_name}",
                "region": "not-applicable",
                "caseTags": ["non-animal", "low-resolution", class_name],
                "sourceDatasetIndex": index,
                "sourceClass": class_name,
            }
        )
        if all(len(values) >= args.images_per_class for values in selected.values()):
            break
    if any(len(values) < args.images_per_class for values in selected.values()):
        raise SystemExit(f"Could not collect requested class counts: {selected}")
    manifest_path = args.output_dir / "benchmark_manifest.jsonl"
    manifest_path.write_text(
        "\n".join(json.dumps(row, sort_keys=True) for row in manifest) + "\n"
    )
    report = {
        "datasetVersion": "cifar10-negative-v1",
        "source": "CIFAR-10 test split",
        "sourceURL": "https://www.cs.toronto.edu/~kriz/cifar.html",
        "limitations": [
            "Images are only 32x32 and are not representative of modern phone photos.",
            "Only four vehicle classes are included; this is a negative-control pilot, not broad open-set calibration.",
        ],
        "selectedIndices": selected,
        "images": len(manifest),
        "manifest": str(manifest_path),
    }
    (args.output_dir / "preparation_report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n"
    )
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
