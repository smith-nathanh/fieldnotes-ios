#!/usr/bin/env python3
"""Download, verify, and install the versioned BioCAP iOS asset bundle."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path


DEFAULT_MANIFEST = Path(
    "tools/biocap/assets/nc-regional-birdnet-travel-v2.json"
)
DEFAULT_OUTPUT = Path("Fieldnotes/Fieldnotes/Resources/BioCAP")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--download-dir",
        type=Path,
        default=Path("tmp/biocap-ios-assets"),
    )
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify(path: Path, expected: dict[str, object]) -> None:
    expected_bytes = int(expected["bytes"])
    if path.stat().st_size != expected_bytes:
        raise SystemExit(
            f"Size mismatch for {path}: {path.stat().st_size} != {expected_bytes}"
        )
    actual_sha = sha256(path)
    if actual_sha != expected["sha256"]:
        raise SystemExit(
            f"SHA-256 mismatch for {path}: {actual_sha} != {expected['sha256']}"
        )


def download(gcs_uri: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    gsutil = shutil.which("gsutil")
    gcloud = shutil.which("gcloud")
    if gsutil:
        command = [gsutil, "cp", gcs_uri, str(destination)]
    elif gcloud:
        command = [gcloud, "storage", "cp", gcs_uri, str(destination)]
    else:
        raise SystemExit("Install Google Cloud CLI (gcloud or gsutil), or pass --archive.")
    subprocess.run(command, check=True)


def safe_extract(archive_path: Path, destination: Path) -> None:
    destination_root = destination.resolve()
    with tarfile.open(archive_path, mode="r:gz") as archive:
        for member in archive.getmembers():
            target = (destination / member.name).resolve()
            if destination_root not in target.parents and target != destination_root:
                raise SystemExit(f"Unsafe archive path: {member.name}")
            if not member.isfile():
                raise SystemExit(f"Unexpected non-file archive member: {member.name}")
        archive.extractall(destination, filter="data")


def main() -> None:
    args = parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    archive_metadata = manifest["archive"]
    archive_path = args.archive
    if archive_path is None:
        archive_path = args.download_dir / str(archive_metadata["filename"])
        if not archive_path.exists():
            download(str(manifest["gcsURI"]), archive_path)
    verify(archive_path, archive_metadata)

    with tempfile.TemporaryDirectory(prefix="fieldnotes-biocap-") as temporary:
        extraction_root = Path(temporary)
        safe_extract(archive_path, extraction_root)
        expected_paths = {str(row["path"]) for row in manifest["files"]}
        actual_paths = {
            path.relative_to(extraction_root).as_posix()
            for path in extraction_root.rglob("*")
            if path.is_file()
        }
        if actual_paths != expected_paths:
            missing = sorted(expected_paths - actual_paths)
            extra = sorted(actual_paths - expected_paths)
            raise SystemExit(f"Archive file list mismatch; missing={missing}, extra={extra}")
        for row in manifest["files"]:
            verify(extraction_root / str(row["path"]), row)

        source = extraction_root / "BioCAP"
        output = args.output_dir.resolve()
        output.mkdir(parents=True, exist_ok=True)
        for name in ("BioCAPConfig.json", "BioCAPSpecies.json", "BioCAPTextEmbeddings.f32"):
            shutil.copy2(source / name, output / name)
        for name in ("Models", "TestFixtures"):
            destination = output / name
            if destination.exists():
                shutil.rmtree(destination)
            shutil.copytree(source / name, destination)

    print(
        json.dumps(
            {
                "assetVersion": manifest["assetVersion"],
                "speciesCount": manifest["config"]["speciesCount"],
                "installedTo": str(args.output_dir),
                "verifiedFiles": len(manifest["files"]),
            },
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
