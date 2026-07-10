from __future__ import annotations

import sys
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

from enrich_fallback_taxonomy import enrich_row  # noqa: E402


class EnrichFallbackTaxonomyTests(unittest.TestCase):
    def test_enrich_row_preserves_existing_metadata_and_adds_lineage(self) -> None:
        row = {"scientificName": "Example bird", "sources": ["birdnet-audio-labels"]}
        taxon = {"id": 3, "name": "Example bird", "ancestor_ids": [1, 2, 3]}
        all_taxa = {
            1: {"id": 1, "rank": "kingdom", "name": "Animalia"},
            2: {"id": 2, "rank": "class", "name": "Aves"},
            3: {"id": 3, "rank": "species", "name": "Example bird"},
        }
        output = enrich_row(row, taxon, all_taxa)
        self.assertEqual(output["kingdom"], "Animalia")
        self.assertEqual(output["class"], "Aves")
        self.assertEqual(output["taxon"], "bird")
        self.assertEqual(output["sources"], ["birdnet-audio-labels"])
        self.assertEqual(output["iNaturalistTaxonID"], 3)


if __name__ == "__main__":
    unittest.main()
