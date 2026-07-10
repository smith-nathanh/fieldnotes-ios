#!/usr/bin/env python3
"""Create contact sheets for visual inspection of validation images."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--image-root",
        type=Path,
        help="Directory containing images, often grouped one subdirectory per taxon.",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        help="Optional JSONL image manifest with path fields.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        required=True,
        help="Directory where contact sheet JPEGs will be written.",
    )
    parser.add_argument("--columns", type=int, default=4)
    parser.add_argument("--rows", type=int, default=6)
    parser.add_argument("--cell-width", type=int, default=240)
    parser.add_argument("--cell-height", type=int, default=210)
    return parser.parse_args()


def images_from_manifest(path: Path) -> list[Path]:
    images = []
    base = path.parent
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        image = Path(record["path"])
        images.append(image if image.is_absolute() else base / image)
    return images


def images_from_root(path: Path) -> list[Path]:
    return sorted(
        image
        for image in path.glob("**/*")
        if image.suffix.lower() in {".jpg", ".jpeg", ".png"}
    )


def label_for(path: Path) -> str:
    parent = path.parent.name
    stem = path.stem
    suffix = stem[-2:] if len(stem) >= 2 else stem
    return f"{parent} {suffix}"


def main() -> None:
    args = parse_args()
    if not args.image_root and not args.manifest:
        raise SystemExit("Provide --image-root or --manifest.")

    images = images_from_manifest(args.manifest) if args.manifest else images_from_root(args.image_root)
    if not images:
        raise SystemExit("No images found.")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    page_size = args.columns * args.rows

    for page, start in enumerate(range(0, len(images), page_size), start=1):
        chunk = images[start:start + page_size]
        sheet = Image.new(
            "RGB",
            (args.cell_width * args.columns, args.cell_height * args.rows),
            "white",
        )
        draw = ImageDraw.Draw(sheet)

        for index, path in enumerate(chunk):
            image = Image.open(path).convert("RGB")
            image.thumbnail((args.cell_width, args.cell_height - 50))
            x = (index % args.columns) * args.cell_width + (args.cell_width - image.width) // 2
            y = (index // args.columns) * args.cell_height
            sheet.paste(image, (x, y))
            draw.text(
                ((index % args.columns) * args.cell_width + 6, y + args.cell_height - 46),
                label_for(path),
                fill=(0, 0, 0),
            )

        output = args.output_dir / f"contact-sheet-{page:02d}.jpg"
        sheet.save(output, quality=92)
        print(output)


if __name__ == "__main__":
    main()
