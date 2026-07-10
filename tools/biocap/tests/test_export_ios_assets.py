from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

from export_ios_assets import build_geography_export, validated_embeddings  # noqa: E402


class ExportIOSAssetsTests(unittest.TestCase):
    def test_geography_export_uses_stable_state_bits_and_region_mapping(self) -> None:
        config, masks = build_geography_export(
            [
                {
                    "scientificName": "Alpha one",
                    "areaCodes": ["US-NC", "US-VA"],
                    "regionIDs": ["southeast"],
                },
                {
                    "scientificName": "Beta two",
                    "areaCodes": ["US-CA"],
                    "regionIDs": ["pacific"],
                },
            ],
            {
                "regions": [
                    {"id": "southeast", "displayName": "Southeast"},
                    {"id": "pacific", "displayName": "Pacific"},
                ],
                "membershipPlaces": [
                    {"code": "US-VA", "regionID": "southeast"},
                    {"code": "US-NC", "regionID": "southeast"},
                    {"code": "US-CA", "regionID": "pacific"},
                ],
            },
        )

        self.assertEqual(config["stateCodes"], ["US-VA", "US-NC", "US-CA"])
        self.assertEqual(config["stateRegionIndices"], [0, 0, 1])
        self.assertEqual(masks.dtype, np.dtype("<u8"))
        self.assertEqual(masks.tolist(), [0b011, 0b100])

    def test_geography_export_rejects_region_membership_mismatch(self) -> None:
        with self.assertRaisesRegex(SystemExit, "regionIDs do not match"):
            build_geography_export(
                [
                    {
                        "scientificName": "Alpha one",
                        "areaCodes": ["US-NC"],
                        "regionIDs": ["pacific"],
                    }
                ],
                {
                    "regions": [
                        {"id": "southeast", "displayName": "Southeast"},
                        {"id": "pacific", "displayName": "Pacific"},
                    ],
                    "membershipPlaces": [
                        {"code": "US-NC", "regionID": "southeast"}
                    ],
                },
            )

    def test_export_rejects_embedding_row_order_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "embeddings.npz"
            rows = np.zeros((2, 512), dtype=np.float32)
            rows[:, 0] = 1
            np.savez(
                path,
                embeddings=rows,
                scientific_names=np.asarray(["Beta two", "Alpha one"]),
            )
            with np.load(path) as archive:
                with self.assertRaisesRegex(SystemExit, "row-order mismatch at index 0"):
                    validated_embeddings(
                        archive,
                        [
                            {"scientificName": "Alpha one"},
                            {"scientificName": "Beta two"},
                        ],
                    )

    def test_export_accepts_exact_finite_unit_rows(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "embeddings.npz"
            rows = np.zeros((2, 512), dtype=np.float32)
            rows[:, 0] = 1
            np.savez(
                path,
                embeddings=rows,
                scientific_names=np.asarray(["Alpha one", "Beta two"]),
            )
            with np.load(path) as archive:
                result = validated_embeddings(
                    archive,
                    [
                        {"scientificName": "Alpha one"},
                        {"scientificName": "Beta two"},
                    ],
                )
            self.assertEqual(result.shape, (2, 512))
            self.assertEqual(result.dtype, np.dtype("<f4"))


if __name__ == "__main__":
    unittest.main()
