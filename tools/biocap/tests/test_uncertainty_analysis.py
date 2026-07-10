from __future__ import annotations

import sys
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

from analyze_biocap_uncertainty import evaluate_case  # noqa: E402


class UncertaintyAnalysisTests(unittest.TestCase):
    def test_small_margin_falls_back_to_shared_genus(self) -> None:
        predictions = [
            {"scientificName": "Lucanus elaphus", "score": 0.380},
            {"scientificName": "Lucanus capreolus", "score": 0.372},
            {"scientificName": "Dorcus parallelus", "score": 0.330},
        ]
        metadata = {
            "Lucanus elaphus": {"genus": "Lucanus", "family": "Lucanidae"},
            "Lucanus capreolus": {"genus": "Lucanus", "family": "Lucanidae"},
            "Dorcus parallelus": {"genus": "Dorcus", "family": "Lucanidae"},
        }

        outcome = evaluate_case(predictions, metadata, 0.035, 0.020)

        self.assertEqual(outcome["rank"], "genus")
        self.assertEqual(outcome["name"], "Lucanus")

    def test_regional_boost_never_removes_fallback(self) -> None:
        predictions = [
            {"scientificName": "Travel bird", "score": 0.380},
            {"scientificName": "Local bird", "score": 0.378},
        ]
        metadata = {
            "Travel bird": {"catalogTier": "travelFallback"},
            "Local bird": {"catalogTier": "regional"},
        }

        outcome = evaluate_case(predictions, metadata, 0.035, 0.020, 0.005)

        self.assertEqual(outcome["topScientificName"], "Local bird")


if __name__ == "__main__":
    unittest.main()
