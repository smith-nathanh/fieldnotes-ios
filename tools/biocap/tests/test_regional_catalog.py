from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

from build_inaturalist_regional_catalog import (  # noqa: E402
    catalog_record,
    merge_membership_records,
    product_taxon,
    reconcile_current_species,
    species_selectors,
    validate_membership_definition,
)


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

    def test_catalog_record_preserves_area_membership_without_duplicate_rows(self) -> None:
        all_taxa = {
            1: {"id": 1, "rank": "kingdom", "name": "Animalia"},
            2: {"id": 2, "rank": "class", "name": "Mammalia"},
            3: {"id": 3, "rank": "genus", "name": "Ursus"},
            4: {"id": 4, "rank": "species", "name": "Ursus americanus"},
        }
        taxon = {
            **all_taxa[4],
            "ancestor_ids": [1, 2, 3, 4],
            "preferred_common_name": "American Black Bear",
            "regional_observations_count": 500,
        }

        row = catalog_record(
            taxon,
            all_taxa,
            "us-regional-v1",
            observation_count_field="usResearchObservations",
            area_observation_counts={"US-VA": 20, "US-NC": 42},
            area_regions={"US-VA": "southeast", "US-NC": "southeast"},
        )

        self.assertEqual(row["usResearchObservations"], 500)
        self.assertEqual(row["areaCodes"], ["US-NC", "US-VA"])
        self.assertEqual(row["areaObservationCounts"], {"US-NC": 42, "US-VA": 20})
        self.assertEqual(row["regionIDs"], ["southeast"])

    def test_us_definition_has_one_entry_for_every_state_and_dc(self) -> None:
        definition_path = TOOLS_DIR / "catalogs" / "us-regional-v1.json"
        definition = json.loads(definition_path.read_text(encoding="utf-8"))
        places, area_regions = validate_membership_definition(definition)

        self.assertEqual(len(places), 51)
        self.assertEqual({int(place["placeID"]) for place in places}, set(range(2, 53)))
        self.assertEqual(area_regions["US-NC"], "southeast")
        self.assertEqual(species_selectors(definition), [("taxon-1", {"taxon_id": 1})])

    def test_existing_iconic_taxon_definition_remains_supported(self) -> None:
        self.assertEqual(
            species_selectors({"iconicTaxa": ["Aves", "Mammalia"]}),
            [
                ("Aves", {"iconic_taxa": "Aves"}),
                ("Mammalia", {"iconic_taxa": "Mammalia"}),
            ],
        )

    def test_membership_definition_rejects_unknown_region(self) -> None:
        with self.assertRaisesRegex(SystemExit, "unknown regionID"):
            validate_membership_definition(
                {
                    "regions": [{"id": "southeast"}],
                    "membershipPlaces": [
                        {
                            "placeID": 30,
                            "code": "US-NC",
                            "name": "North Carolina",
                            "regionID": "other",
                        }
                    ],
                }
            )

    def test_state_union_retains_new_active_taxon_missing_from_parent_page(self) -> None:
        species = {
            1: {"id": 1, "name": "Known species", "regional_observations_count": 10}
        }
        memberships: dict[int, dict[str, int]] = {}
        state_species = {
            2: {"id": 2, "name": "Newly active species", "regional_observations_count": 4}
        }

        added = merge_membership_records(
            species,
            memberships,
            state_species,
            "US-FL",
        )

        self.assertEqual(added, {2})
        self.assertIn(2, species)
        self.assertEqual(memberships[2], {"US-FL": 4})

    def test_current_taxonomy_replaces_stale_name_and_merges_area_evidence(self) -> None:
        species = {
            10: {
                "id": 10,
                "name": "Old genus species",
                "regional_observations_count": 12,
            },
            20: {
                "id": 20,
                "name": "New genus species",
                "regional_observations_count": 9,
            },
        }
        memberships = {10: {"US-AR": 3}, 20: {"US-NC": 9}}
        current = {
            10: {
                "id": 10,
                "name": "Old genus species",
                "is_active": False,
                "current_synonymous_taxon_ids": [20],
            },
            20: {"id": 20, "name": "New genus species", "is_active": True},
        }

        report = reconcile_current_species(species, memberships, current)

        self.assertNotIn(10, species)
        self.assertEqual(species[20]["regional_observations_count"], 12)
        self.assertEqual(species[20]["catalog_synonyms"], ["Old genus species"])
        self.assertEqual(memberships[20], {"US-AR": 3, "US-NC": 9})
        self.assertEqual(report["inactiveRowsReplaced"], 1)


if __name__ == "__main__":
    unittest.main()
