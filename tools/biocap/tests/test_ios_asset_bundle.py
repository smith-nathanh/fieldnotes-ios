from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
PACKAGER = TOOLS_DIR / "package_ios_assets.py"
INSTALLER = TOOLS_DIR / "install_ios_assets.py"


class IOSAssetBundleTests(unittest.TestCase):
    def test_package_and_install_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            (source / "Models" / "Example.mlpackage").mkdir(parents=True)
            (source / "TestFixtures").mkdir()
            config = {
                "modelName": "example/model",
                "speciesCount": 1,
                "embeddingDim": 2,
                "embeddingDtype": "float32",
                "promptPreset": "test",
                "promptTemplateCount": 1,
                "labelTextType": "scientific",
                "geography": {
                    "stateCodes": ["US-NC"],
                    "stateDisplayNames": ["North Carolina"],
                    "stateRegionIndices": [0],
                    "regions": [{"id": "southeast", "displayName": "Southeast"}],
                },
            }
            (source / "BioCAPConfig.json").write_text(json.dumps(config))
            (source / "BioCAPSpecies.json").write_text("[]")
            (source / "BioCAPTextEmbeddings.f32").write_bytes(b"12345678")
            (source / "BioCAPGeography.bin").write_bytes(b"\x01\x00\x00\x00\x00\x00\x00\x00")
            (source / "Models" / "Example.mlpackage" / "model.bin").write_bytes(b"model")
            (source / "TestFixtures" / "fixture.jpg").write_bytes(b"fixture")
            archive = root / "assets.tar.gz"
            manifest = root / "manifest.json"
            output = root / "installed"

            subprocess.run(
                [
                    sys.executable,
                    str(PACKAGER),
                    "--input-dir",
                    str(source),
                    "--version",
                    "test-v1",
                    "--gcs-uri",
                    "gs://example/assets.tar.gz",
                    "--archive",
                    str(archive),
                    "--manifest",
                    str(manifest),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run(
                [
                    sys.executable,
                    str(INSTALLER),
                    "--manifest",
                    str(manifest),
                    "--archive",
                    str(archive),
                    "--output-dir",
                    str(output),
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            self.assertEqual((output / "BioCAPTextEmbeddings.f32").read_bytes(), b"12345678")
            self.assertEqual(
                (output / "BioCAPGeography.bin").read_bytes(),
                b"\x01\x00\x00\x00\x00\x00\x00\x00",
            )
            self.assertEqual(
                (output / "Models" / "Example.mlpackage" / "model.bin").read_bytes(),
                b"model",
            )


if __name__ == "__main__":
    unittest.main()
