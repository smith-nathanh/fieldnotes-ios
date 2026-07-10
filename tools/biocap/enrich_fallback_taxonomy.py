#!/usr/bin/env python3
"""Fill missing species hierarchy from cached iNaturalist taxon IDs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from build_inaturalist_regional_catalog import RANKS, load_taxa, product_taxon


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--species-list", type=Path, required=True)
    parser.add_argument("--inaturalist-map", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=Path("tmp/biocap-catalogs/inaturalist-cache"),
    )
    parser.add_argument("--sleep-seconds", type=float, default=1.0)
    return parser.parse_args()


def read_jsonl(path: Path) -> list[dict[str, object]]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def enrich_row(
    row: dict[str, object],
    taxon: dict[str, object],
    all_taxa: dict[int, dict[str, object]],
) -> dict[str, object]:
    output = dict(row)
    lineage = [int(value) for value in taxon.get("ancestor_ids") or []]
    if int(taxon["id"]) not in lineage:
        lineage.append(int(taxon["id"]))
    taxonomy = {
        str(all_taxa[taxon_id].get("rank")): str(all_taxa[taxon_id].get("name"))
        for taxon_id in lineage
        if taxon_id in all_taxa and all_taxa[taxon_id].get("rank") in RANKS
    }
    for rank in RANKS:
        if taxonomy.get(rank):
            output[rank] = taxonomy[rank]
    output["taxon"] = product_taxon(taxonomy)
    output["iNaturalistTaxonID"] = int(taxon["id"])
    output["taxonomySources"] = [
        {"name": "iNaturalist", "taxonID": int(taxon["id"]), "match": "exactScientificName"}
    ]
    return output


def write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "\n".join(json.dumps(row, sort_keys=True) for row in rows) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    args = parse_args()
    rows = read_jsonl(args.species_list)
    mapping_rows = read_jsonl(args.inaturalist_map)
    taxon_id_by_name = {
        str(row["scientificName"]): int(row["sourceTaxonId"])
        for row in mapping_rows
        if row.get("scientificName") and row.get("sourceTaxonId")
    }
    missing = [row for row in rows if not row.get("kingdom")]
    mapped = {
        str(row["scientificName"]): taxon_id_by_name[str(row["scientificName"])]
        for row in missing
        if str(row["scientificName"]) in taxon_id_by_name
    }
    species_taxa = load_taxa(
        set(mapped.values()),
        cache_dir=args.cache_dir,
        batch_size=30,
        refresh=False,
        sleep_seconds=args.sleep_seconds,
    )
    ancestor_ids = {
        int(value)
        for taxon in species_taxa.values()
        for value in taxon.get("ancestor_ids") or []
    }
    all_taxa = dict(species_taxa)
    all_taxa.update(
        load_taxa(
            ancestor_ids - species_taxa.keys(),
            cache_dir=args.cache_dir,
            batch_size=30,
            refresh=False,
            sleep_seconds=args.sleep_seconds,
        )
    )
    enriched = []
    for row in rows:
        name = str(row["scientificName"])
        taxon_id = mapped.get(name)
        if taxon_id is None:
            enriched.append(row)
            continue
        taxon = species_taxa[taxon_id]
        if str(taxon.get("name")) != name:
            raise SystemExit(
                f"iNaturalist exact-name mapping drifted for {name}: {taxon.get('name')}"
            )
        enriched.append(enrich_row(row, taxon, all_taxa))
    if [row["scientificName"] for row in enriched] != [row["scientificName"] for row in rows]:
        raise SystemExit("Enrichment changed species row order")
    unresolved = [str(row["scientificName"]) for row in enriched if not row.get("kingdom")]
    write_jsonl(args.output, enriched)
    report = {
        "rows": len(rows),
        "initialMissingHierarchy": len(missing),
        "enrichedRows": len(mapped),
        "unresolvedRows": len(unresolved),
        "unresolvedScientificNames": unresolved,
        "rowOrderPreserved": True,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
