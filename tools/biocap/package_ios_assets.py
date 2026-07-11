#!/usr/bin/env python3
"""Create a checksum-manifested archive of generated BioCAP iOS resources."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import tarfile
from pathlib import Path


DEFAULT_INPUT = Path("Fieldnotes/Fieldnotes/Resources/BioCAP")
GENERATED_PATHS = (
    "BioCAPConfig.json",
    "BioCAPSpecies.json",
    "BioCAPTextEmbeddings.f32",
    "THIRD_PARTY_NOTICES.md",
    "Models",
    "TestFixtures",
)
OPTIONAL_GENERATED_PATHS = ("BioCAPGeography.bin",)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--version", required=True)
    parser.add_argument("--gcs-uri")
    parser.add_argument("--download-url")
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def generated_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for name in GENERATED_PATHS:
        path = root / name
        if not path.exists():
            raise SystemExit(f"Missing generated BioCAP asset: {path}")
        if path.is_file():
            files.append(path)
        else:
            files.extend(item for item in path.rglob("*") if item.is_file())
    files.extend(root / name for name in OPTIONAL_GENERATED_PATHS if (root / name).is_file())
    return sorted(files, key=lambda path: path.relative_to(root).as_posix())


def add_file(archive: tarfile.TarFile, path: Path, arcname: str) -> None:
    info = archive.gettarinfo(str(path), arcname=arcname)
    info.uid = 0
    info.gid = 0
    info.uname = ""
    info.gname = ""
    info.mtime = 0
    with path.open("rb") as handle:
        archive.addfile(info, handle)


def main() -> None:
    args = parse_args()
    root = args.input_dir.resolve()
    files = generated_files(root)
    config = json.loads((root / "BioCAPConfig.json").read_text(encoding="utf-8"))

    args.archive.parent.mkdir(parents=True, exist_ok=True)
    with args.archive.open("wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w") as archive:
                for path in files:
                    relative = path.relative_to(root).as_posix()
                    add_file(archive, path, f"BioCAP/{relative}")

    manifest = {
        "schemaVersion": 1,
        "assetVersion": args.version,
        "archive": {
            "filename": args.archive.name,
            "bytes": args.archive.stat().st_size,
            "sha256": sha256(args.archive),
        },
        "config": {
            "modelName": config["modelName"],
            "speciesCount": config["speciesCount"],
            "embeddingDim": config["embeddingDim"],
            "embeddingDtype": config["embeddingDtype"],
            "promptPreset": config["promptPreset"],
            "promptTemplateCount": config["promptTemplateCount"],
            "labelTextType": config["labelTextType"],
            "geography": config.get("geography"),
        },
        "files": [
            {
                "path": f"BioCAP/{path.relative_to(root).as_posix()}",
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
            for path in files
        ],
    }
    if args.gcs_uri:
        manifest["gcsURI"] = args.gcs_uri
    if args.download_url:
        manifest["downloadURL"] = args.download_url
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
