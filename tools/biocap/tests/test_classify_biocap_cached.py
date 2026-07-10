from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

from classify_biocap_cached import load_text_matrix, metric_summary  # noqa: E402
from validate_biocap import Species  # noqa: E402


def species(name: str) -> Species:
    return Species(
        scientific_name=name,
        common_name=name,
        taxon="animal",
        family="Exampleidae",
        genus=name.split()[0],
    )


def result_row(*, in_catalog: bool, rank: int | None) -> dict[str, object]:
    return {
        "inCatalog": in_catalog,
        "expectedRank": rank,
        "taxonomicHits": {
            taxon_rank: {"top1": True, "top3": True, "top10": True}
            for taxon_rank in ("genus", "family")
        },
    }


class CachedBenchmarkTests(unittest.TestCase):
    def test_embedding_archive_requires_exact_species_order(self) -> None:
        rows = [species("Alpha one"), species("Beta two")]
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "embeddings.npz"
            np.savez(
                archive,
                embeddings=np.ones((2, 512), dtype=np.float32),
                scientific_names=np.asarray(["Beta two", "Alpha one"]),
            )
            with self.assertRaisesRegex(SystemExit, "row-order mismatch at index 0"):
                load_text_matrix(archive, rows)

    def test_out_of_catalog_images_count_against_all_image_accuracy(self) -> None:
        summary = metric_summary(
            [
                result_row(in_catalog=True, rank=1),
                result_row(in_catalog=True, rank=4),
                result_row(in_catalog=False, rank=None),
            ]
        )
        self.assertEqual(summary["catalogCoverage"], 2 / 3)
        self.assertEqual(summary["speciesTop1All"], 1 / 3)
        self.assertEqual(summary["speciesTop1InCatalog"], 1 / 2)
        self.assertEqual(summary["speciesTop3All"], 1 / 3)
        self.assertEqual(summary["speciesTop10All"], 2 / 3)
        self.assertEqual(summary["forcedPredictionRateOnOutOfCatalog"], 1.0)


if __name__ == "__main__":
    unittest.main()
