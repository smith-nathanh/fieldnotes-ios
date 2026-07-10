from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

from merge_biocap_embedding_catalogs import merge_catalogs, validate_matching_config  # noqa: E402


class MergeCatalogTests(unittest.TestCase):
    def test_merge_prefers_regional_row_and_tags_fallback(self) -> None:
        regional = [{"scientificName": "Alpha one", "sources": [{"name": "regional"}]}]
        fallback = [
            {"scientificName": "Alpha one", "sources": ["birdnet-audio-labels"]},
            {"scientificName": "Beta two", "sources": ["birdnet-audio-labels"]},
            {"scientificName": "Gamma three", "sources": ["other"]},
        ]
        rows, matrix, report = merge_catalogs(
            regional,
            np.asarray([[1.0, 0.0]], dtype=np.float32),
            fallback,
            np.asarray([[0.0, 1.0], [0.5, 0.5], [0.2, 0.8]], dtype=np.float32),
            "birdnet-audio-labels",
        )
        self.assertEqual([row["scientificName"] for row in rows], ["Alpha one", "Beta two"])
        self.assertEqual(rows[0]["catalogTier"], "regional")
        self.assertTrue(rows[0]["alsoInTravelFallback"])
        self.assertEqual(rows[1]["catalogTier"], "travelFallback")
        np.testing.assert_array_equal(matrix[0], np.asarray([1.0, 0.0]))
        self.assertEqual(report["overlapRows"], 1)
        self.assertEqual(report["fallbackOnlyRows"], 1)

    def test_config_mismatch_fails(self) -> None:
        with self.assertRaisesRegex(SystemExit, "prompt_preset"):
            validate_matching_config(
                {
                    "model_name": np.asarray(["model"]),
                    "prompt_templates": np.asarray(["a"]),
                    "label_text_type": np.asarray(["scientific"]),
                    "prompt_preset": np.asarray(["one"]),
                },
                {
                    "model_name": np.asarray(["model"]),
                    "prompt_templates": np.asarray(["a"]),
                    "label_text_type": np.asarray(["scientific"]),
                    "prompt_preset": np.asarray(["two"]),
                },
            )

    def test_required_hierarchy_excludes_audio_event(self) -> None:
        rows, _, report = merge_catalogs(
            [],
            np.empty((0, 2), dtype=np.float32),
            [
                {"scientificName": "Alpha one", "kingdom": "Animalia", "sources": ["birdnet-audio-labels"]},
                {"scientificName": "Engine", "sources": ["birdnet-audio-labels"]},
            ],
            np.asarray([[1.0, 0.0], [0.0, 1.0]], dtype=np.float32),
            "birdnet-audio-labels",
            True,
        )
        self.assertEqual([row["scientificName"] for row in rows], ["Alpha one"])
        self.assertEqual(report["selectedFallbackRows"], 1)


if __name__ == "__main__":
    unittest.main()
