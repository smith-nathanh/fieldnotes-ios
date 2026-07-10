from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

from quantize_biocap_embeddings import quantize_archive  # noqa: E402


class QuantizeBioCAPEmbeddingsTests(unittest.TestCase):
    def test_quantize_preserves_metadata_and_reports_ranking_parity(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.npz"
            output = root / "float16.npz"
            queries = root / "queries.npz"
            matrix = np.eye(4, dtype=np.float32)
            np.savez_compressed(
                source,
                embeddings=matrix,
                scientific_names=np.asarray(["A", "B", "C", "D"]),
                model_name=np.asarray(["model"]),
            )
            np.savez_compressed(queries, embeddings=matrix[:2])

            report = quantize_archive(source, output, queries, top_k=2)

            with np.load(output) as archive:
                self.assertEqual(archive["embeddings"].dtype, np.float16)
                self.assertEqual(archive["scientific_names"].tolist(), ["A", "B", "C", "D"])
                self.assertEqual(archive["model_name"].tolist(), ["model"])
            self.assertEqual(report["outputBytes"], report["inputBytes"] // 2)
            self.assertEqual(report["rankingParity"]["top1Parity"], 1.0)
            self.assertEqual(report["rankingParity"]["topKSetParity"], 1.0)

    def test_quantize_rejects_non_float32_canonical_input(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.npz"
            np.savez_compressed(source, embeddings=np.eye(2, dtype=np.float16))

            with self.assertRaisesRegex(SystemExit, "must be float32"):
                quantize_archive(source, root / "output.npz")


if __name__ == "__main__":
    unittest.main()
