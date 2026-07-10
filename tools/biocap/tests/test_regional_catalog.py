from __future__ import annotations

import sys
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

from build_inaturalist_regional_catalog import catalog_record, product_taxon  # noqa: E402


class RegionalCatalogTests(unittest.TestCase):
    def test_product_taxon_maps_missing_local_groups(self) -> None:
        self.assertEqual(product_taxon({"class": "Actinopterygii"}), "fish")
        self.assertEqual(product_taxon({"class": "Arachnida"}), "arachnid")
        self.assertEqual(product_taxon({"phylum": "Mollusca"}), "mollusk")
        self.assertEqual(
            product_taxon({"class": "Malacostraca", "order": "Decapoda"}),
            "crustacean",
        )

    def test_catalog_record_preserves_hierarchy_and_provenance(self) -> None:
        all_taxa = {
            1: {"id": 1, "rank": "kingdom", "name": "Animalia"},
            2: {"id": 2, "rank": "class", "name": "Arachnida"},
            3: {"id": 3, "rank": "family", "name": "Araneidae"},
            4: {"id": 4, "rank": "genus", "name": "Argiope"},
            5: {"id": 5, "rank": "species", "name": "Argiope aurantia"},
        }
        taxon = {
            **all_taxa[5],
            "ancestor_ids": [1, 2, 3, 4, 5],
            "preferred_common_name": "Yellow Garden Spider",
            "regional_observations_count": 42,
        }
        row = catalog_record(taxon, all_taxa, "nc-regional-v1")
        self.assertEqual(row["scientificName"], "Argiope aurantia")
        self.assertEqual(row["class"], "Arachnida")
        self.assertEqual(row["family"], "Araneidae")
        self.assertEqual(row["taxon"], "arachnid")
        self.assertEqual(row["sources"][0]["taxonID"], 5)


if __name__ == "__main__":
    unittest.main()
