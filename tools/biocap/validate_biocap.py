#!/usr/bin/env python3
"""Validate BioCAP cached text embeddings and isolated image encoder parity.

This is a Phase 0 workstation harness. It does not integrate anything into the
iOS app. It proves that:

1. Text embeddings can be precomputed, saved, reloaded, and used for the same
   image rankings as the full OpenCLIP BioCAP model.
2. The isolated vision tower output matches `model.encode_image`.
3. Optionally, a Core ML export of the normalized vision tower matches PyTorch.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np
from PIL import Image
import torch
import torch.nn.functional as F

try:
    import open_clip
except ImportError as exc:  # pragma: no cover - exercised by local env setup
    raise SystemExit(
        "Missing dependency open_clip_torch. Install with:\n"
        "  python -m pip install -r tools/biocap/requirements.txt"
    ) from exc


MODEL_NAME = "hf-hub:imageomics/biocap"
PARITY_PROMPT = "a photo of {scientific_name}"
BIOCAP_OPENAI_TEMPLATES = [
    "a photo of {label_text}.",
    "a bad photo of a {label_text}.",
    "a photo of many {label_text}.",
    "a sculpture of a {label_text}.",
    "a photo of the hard to see {label_text}.",
    "a low resolution photo of the {label_text}.",
    "a rendering of a {label_text}.",
    "graffiti of a {label_text}.",
    "a bad photo of the {label_text}.",
    "a cropped photo of the {label_text}.",
    "a tattoo of a {label_text}.",
    "the embroidered {label_text}.",
    "a photo of a hard to see {label_text}.",
    "a bright photo of a {label_text}.",
    "a photo of a clean {label_text}.",
    "a photo of a dirty {label_text}.",
    "a dark photo of the {label_text}.",
    "a drawing of a {label_text}.",
    "a photo of my {label_text}.",
    "the plastic {label_text}.",
    "a photo of the cool {label_text}.",
    "a close-up photo of a {label_text}.",
    "a black and white photo of the {label_text}.",
    "a painting of the {label_text}.",
    "a painting of a {label_text}.",
    "a pixelated photo of the {label_text}.",
    "a sculpture of the {label_text}.",
    "a bright photo of the {label_text}.",
    "a cropped photo of a {label_text}.",
    "a plastic {label_text}.",
    "a photo of the dirty {label_text}.",
    "a jpeg corrupted photo of a {label_text}.",
    "a blurry photo of the {label_text}.",
    "a photo of the {label_text}.",
    "a good photo of the {label_text}.",
    "a rendering of the {label_text}.",
    "a {label_text} in a video game.",
    "a photo of one {label_text}.",
    "a doodle of a {label_text}.",
    "a close-up photo of the {label_text}.",
    "a photo of a {label_text}.",
    "the origami {label_text}.",
    "the {label_text} in a video game.",
    "a sketch of a {label_text}.",
    "a doodle of the {label_text}.",
    "a origami {label_text}.",
    "a low resolution photo of a {label_text}.",
    "the toy {label_text}.",
    "a rendition of the {label_text}.",
    "a photo of the clean {label_text}.",
    "a photo of a large {label_text}.",
    "a rendition of a {label_text}.",
    "a photo of a nice {label_text}.",
    "a photo of a weird {label_text}.",
    "a blurry photo of a {label_text}.",
    "a cartoon {label_text}.",
    "art of a {label_text}.",
    "a sketch of the {label_text}.",
    "a embroidered {label_text}.",
    "a pixelated photo of a {label_text}.",
    "itap of the {label_text}.",
    "a jpeg corrupted photo of the {label_text}.",
    "a good photo of a {label_text}.",
    "a plushie {label_text}.",
    "a photo of the nice {label_text}.",
    "a photo of the small {label_text}.",
    "a photo of the weird {label_text}.",
    "the cartoon {label_text}.",
    "art of the {label_text}.",
    "a drawing of the {label_text}.",
    "a photo of the large {label_text}.",
    "a black and white photo of a {label_text}.",
    "the plushie {label_text}.",
    "a dark photo of a {label_text}.",
    "itap of a {label_text}.",
    "graffiti of the {label_text}.",
    "a toy {label_text}.",
    "itap of my {label_text}.",
    "a photo of a cool {label_text}.",
    "a photo of a small {label_text}.",
    "a tattoo of the {label_text}.",
]


@dataclass(frozen=True)
class Species:
    scientific_name: str
    common_name: str
    taxon: str
    kingdom: str = ""
    phylum: str = ""
    class_name: str = ""
    order: str = ""
    family: str = ""
    genus: str = ""
    species: str = ""


@dataclass(frozen=True)
class ImageCase:
    path: Path
    expected_scientific_name: str | None = None


class NormalizedVisionEncoder(torch.nn.Module):
    """Vision tower wrapper matching BioCAP/OpenCLIP image embedding output."""

    def __init__(self, model: torch.nn.Module) -> None:
        super().__init__()
        self.visual = model.visual

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        return F.normalize(self.visual(image), dim=-1)


class ManualNormalizedVisionEncoder(torch.nn.Module):
    """Export-oriented BioCAP vision path with explicit attention primitives."""

    def __init__(self, model: torch.nn.Module) -> None:
        super().__init__()
        visual = model.visual
        if visual.attn_pool is not None or visual.pool_type != "tok":
            raise ValueError("Manual export wrapper only supports BioCAP ViT token pooling.")

        self.conv1 = visual.conv1
        self.ln_pre = visual.ln_pre
        self.resblocks = visual.transformer.resblocks
        self.ln_post = visual.ln_post
        self.class_embedding = visual.class_embedding
        self.positional_embedding = visual.positional_embedding
        self.proj = visual.proj
        self.batch_size = 1
        self.width = int(visual.conv1.out_channels)
        self.patch_count = int(visual.grid_size[0] * visual.grid_size[1])
        self.token_count = self.patch_count + 1

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        x = self.conv1(image)
        x = x.reshape(self.batch_size, self.width, self.patch_count)
        x = x.permute(0, 2, 1)

        class_embedding = self.class_embedding.reshape(1, 1, self.width)
        x = torch.cat([class_embedding.to(x.dtype), x], dim=1)
        x = x + self.positional_embedding.to(x.dtype)
        x = self.ln_pre(x)

        for block in self.resblocks:
            attention_input = block.ln_1(x)
            x = x + block.ls_1(self._attention(block.attn, attention_input))
            x = x + block.ls_2(block.mlp(block.ln_2(x)))

        x = self.ln_post(x)
        pooled = x[:, 0, :]
        pooled = pooled @ self.proj
        return F.normalize(pooled, dim=-1)

    @staticmethod
    def _attention(attn: torch.nn.MultiheadAttention, x: torch.Tensor) -> torch.Tensor:
        embed_dim = attn.embed_dim
        head_count = attn.num_heads
        head_dim = embed_dim // head_count
        batch_size = 1
        token_count = 197

        qkv = F.linear(x, attn.in_proj_weight, attn.in_proj_bias)
        q, k, v = qkv.split(embed_dim, dim=-1)
        q = q.reshape(batch_size, token_count, head_count, head_dim).transpose(1, 2)
        k = k.reshape(batch_size, token_count, head_count, head_dim).transpose(1, 2)
        v = v.reshape(batch_size, token_count, head_count, head_dim).transpose(1, 2)

        scale = float(head_dim) ** -0.5
        weights = torch.matmul(q * scale, k.transpose(-2, -1))
        weights = torch.softmax(weights, dim=-1)
        output = torch.matmul(weights, v)
        output = output.transpose(1, 2).reshape(batch_size, token_count, embed_dim)
        return attn.out_proj(output)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--species-list",
        type=Path,
        required=True,
        help="JSONL/JSON/CSV species list with scientificName, commonName, taxon.",
    )
    parser.add_argument(
        "--images",
        nargs="*",
        type=Path,
        default=[],
        help="Image files to classify.",
    )
    parser.add_argument(
        "--image-manifest",
        type=Path,
        help="Optional JSONL/CSV manifest with path and expectedScientificName.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("tmp/biocap-validation"),
        help="Directory for embeddings, rankings, and parity report.",
    )
    parser.add_argument(
        "--prompt-template",
        action="append",
        default=None,
        help=(
            "Custom prompt template. May be repeated. Fields: {label_text}, "
            "{scientific_name}, {common_name}, {taxon}. Overrides --prompt-preset."
        ),
    )
    parser.add_argument(
        "--prompt-preset",
        choices=["biocap-openai", "simple"],
        default="biocap-openai",
        help="Prompt template set. biocap-openai matches BioCAP zero-shot evaluation.",
    )
    parser.add_argument(
        "--label-text-type",
        choices=["scientific", "common", "scientific_common", "taxon", "taxon_common"],
        default="scientific",
        help=(
            "Class text inserted into prompt templates. BioCAP used taxon_common "
            "for camera-trap/rare-species and as-is labels for NABirds/Meta-Album."
        ),
    )
    parser.add_argument(
        "--top-k",
        type=int,
        default=5,
        help="Top-k rankings to compare.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=64,
        help="Text prompt embedding batch size.",
    )
    parser.add_argument(
        "--species-batch-size",
        type=int,
        default=128,
        help="Number of species to render before batched text embedding.",
    )
    parser.add_argument(
        "--device",
        choices=["auto", "cpu", "mps", "cuda"],
        default="auto",
        help="Torch device.",
    )
    parser.add_argument(
        "--embedding-dtype",
        choices=["float32", "float16"],
        default="float32",
        help="Saved text embedding dtype.",
    )
    parser.add_argument(
        "--trace-vision",
        action="store_true",
        help="Trace the isolated normalized vision tower and compare output.",
    )
    parser.add_argument(
        "--export-coreml",
        type=Path,
        help="Optional .mlpackage output path for Core ML vision encoder export.",
    )
    parser.add_argument(
        "--coreml-export-path",
        choices=["manual", "openclip"],
        default="manual",
        help=(
            "Vision wrapper to convert for Core ML. manual expands attention into "
            "primitive ops; openclip converts the traced OpenCLIP visual module."
        ),
    )
    parser.add_argument(
        "--tolerance",
        type=float,
        default=1e-4,
        help="Maximum allowed absolute delta for normalized embedding/similarity parity.",
    )
    return parser.parse_args()


def choose_device(name: str) -> torch.device:
    if name == "cpu":
        return torch.device("cpu")
    if name == "cuda":
        if not torch.cuda.is_available():
            raise SystemExit("CUDA requested but unavailable.")
        return torch.device("cuda")
    if name == "mps":
        if not torch.backends.mps.is_available():
            raise SystemExit("MPS requested but unavailable.")
        return torch.device("mps")
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


def load_species(path: Path) -> list[Species]:
    if path.suffix.lower() == ".jsonl":
        records = [
            json.loads(line)
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
    elif path.suffix.lower() == ".json":
        records = json.loads(path.read_text(encoding="utf-8"))
    elif path.suffix.lower() == ".csv":
        with path.open(newline="", encoding="utf-8") as handle:
            records = list(csv.DictReader(handle))
    else:
        raise SystemExit(f"Unsupported species list format: {path}")

    species = []
    for record in records:
        scientific_name = record.get("scientificName") or record.get("scientific_name")
        if not scientific_name:
            raise SystemExit(f"Species row missing scientificName: {record}")
        species.append(
            Species(
                scientific_name=scientific_name,
                common_name=record.get("commonName")
                or record.get("common_name")
                or scientific_name,
                taxon=record.get("taxon") or "unknown",
                kingdom=record.get("kingdom") or "",
                phylum=record.get("phylum") or "",
                class_name=record.get("class") or record.get("className") or record.get("cls") or "",
                order=record.get("order") or "",
                family=record.get("family") or "",
                genus=record.get("genus") or "",
                species=record.get("species") or "",
            )
        )
    if not species:
        raise SystemExit("Species list is empty.")
    return species


def load_image_cases(image_paths: list[Path], manifest: Path | None) -> list[ImageCase]:
    cases = [ImageCase(path=path) for path in image_paths]
    if not manifest:
        return cases

    if manifest.suffix.lower() == ".jsonl":
        records = [
            json.loads(line)
            for line in manifest.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
    elif manifest.suffix.lower() == ".csv":
        with manifest.open(newline="", encoding="utf-8") as handle:
            records = list(csv.DictReader(handle))
    else:
        raise SystemExit(f"Unsupported image manifest format: {manifest}")

    base = manifest.parent
    for record in records:
        raw_path = record.get("path") or record.get("image") or record.get("imagePath")
        if not raw_path:
            raise SystemExit(f"Image manifest row missing path: {record}")
        path = Path(raw_path)
        if not path.is_absolute():
            path = base / path
        expected = (
            record.get("expectedScientificName")
            or record.get("scientificName")
            or record.get("expected_scientific_name")
        )
        cases.append(ImageCase(path=path, expected_scientific_name=expected))
    return cases


def taxonomic_name(species: Species) -> str:
    parts = [
        species.kingdom,
        species.phylum,
        species.class_name,
        species.order,
        species.family,
        species.genus,
        species.species,
    ]
    compact = [part.strip() for part in parts if part and part.strip()]
    if compact:
        return " ".join(compact)
    return species.scientific_name


def label_text(species: Species, text_type: str) -> str:
    if text_type == "common":
        return species.common_name
    if text_type == "scientific_common":
        if species.common_name and species.common_name != species.scientific_name:
            return f"{species.scientific_name} with common name {species.common_name}"
        return species.scientific_name
    if text_type == "taxon":
        return taxonomic_name(species)
    if text_type == "taxon_common":
        taxon_name = taxonomic_name(species)
        if species.common_name and species.common_name != species.scientific_name:
            return f"{taxon_name} with common name {species.common_name}"
        return taxon_name
    return species.scientific_name


def render_prompts(species: Species, templates: list[str], text_type: str) -> list[str]:
    rendered_label = label_text(species, text_type)
    return [
        template.format(
            label_text=rendered_label,
            scientific_name=species.scientific_name,
            common_name=species.common_name,
            taxon=species.taxon,
        )
        for template in templates
    ]


def batched(items: list[str], size: int) -> Iterable[list[str]]:
    for index in range(0, len(items), size):
        yield items[index : index + size]


def encode_text_matrix(
    model: torch.nn.Module,
    tokenizer,
    species: list[Species],
    templates: list[str],
    label_text_type: str,
    batch_size: int,
    species_batch_size: int,
    device: torch.device,
) -> np.ndarray:
    rows: list[torch.Tensor] = []
    with torch.inference_mode():
        for start in range(0, len(species), species_batch_size):
            species_batch = species[start : start + species_batch_size]
            prompts = [
                prompt
                for item in species_batch
                for prompt in render_prompts(item, templates, label_text_type)
            ]
            prompt_features = []
            for batch in batched(prompts, batch_size):
                tokens = tokenizer(batch).to(device)
                features = model.encode_text(tokens)
                prompt_features.append(F.normalize(features, dim=-1).cpu())
            stacked = torch.cat(prompt_features, dim=0)
            stacked = stacked.reshape(len(species_batch), len(templates), -1)
            rows.append(F.normalize(stacked.mean(dim=1), dim=-1))
            print(
                f"encoded text embeddings for {start + len(species_batch)}/{len(species)} species",
                file=sys.stderr,
            )
    return torch.cat(rows, dim=0).numpy().astype(np.float32)


def encode_image(
    model: torch.nn.Module,
    preprocess,
    image_path: Path,
    device: torch.device,
) -> torch.Tensor:
    image = Image.open(image_path).convert("RGB")
    tensor = preprocess(image).unsqueeze(0).to(device)
    with torch.inference_mode():
        features = model.encode_image(tensor)
        return F.normalize(features, dim=-1).cpu()[0]


def encode_image_with_vision_tower(
    vision: torch.nn.Module,
    preprocess,
    image_path: Path,
    device: torch.device,
) -> torch.Tensor:
    image = Image.open(image_path).convert("RGB")
    tensor = preprocess(image).unsqueeze(0).to(device)
    with torch.inference_mode():
        return vision(tensor).cpu()[0]


def topk(scores: np.ndarray, species: list[Species], k: int) -> list[dict[str, object]]:
    count = min(k, scores.shape[0])
    indices = np.argsort(-scores)[:count]
    return [
        {
            "rank": rank,
            "scientificName": species[index].scientific_name,
            "commonName": species[index].common_name,
            "taxon": species[index].taxon,
            "score": float(scores[index]),
        }
        for rank, index in enumerate(indices, start=1)
    ]


def expected_rank(scores: np.ndarray, species: list[Species], expected: str | None) -> int | None:
    if expected is None:
        return None
    order = np.argsort(-scores)
    for rank, index in enumerate(order, start=1):
        if species[index].scientific_name == expected:
            return rank
    return None


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def compare_coreml(
    export_path: Path,
    traced: torch.jit.ScriptModule,
    example: torch.Tensor,
    pytorch_output: torch.Tensor,
) -> float:
    try:
        import coremltools as ct
    except ImportError as exc:
        raise SystemExit(
            "coremltools is required for --export-coreml. Use Python 3.11/3.12 "
            "and install tools/biocap/requirements.txt."
        ) from exc

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="image", shape=example.shape)],
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
    )
    export_path.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(export_path))

    prediction = mlmodel.predict({"image": example.cpu().numpy()})
    output = next(iter(prediction.values()))
    coreml_output = torch.from_numpy(np.asarray(output)).reshape(pytorch_output.shape)
    return float(torch.max(torch.abs(coreml_output - pytorch_output.cpu())).item())


def disable_torch_fused_attention_for_export() -> None:
    mha_backend = getattr(torch.backends, "mha", None)
    if mha_backend is not None and hasattr(mha_backend, "set_fastpath_enabled"):
        mha_backend.set_fastpath_enabled(False)


def main() -> None:
    args = parse_args()
    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    if args.prompt_template:
        templates = args.prompt_template
        prompt_preset = "custom"
    elif args.prompt_preset == "simple":
        templates = [PARITY_PROMPT]
        prompt_preset = "simple"
    else:
        templates = BIOCAP_OPENAI_TEMPLATES
        prompt_preset = "biocap-openai"

    if prompt_preset == "simple":
        print(
            "warning: using simple parity prompt instead of BioCAP's official "
            "zero-shot prompt ensemble.",
            file=sys.stderr,
        )

    species = load_species(args.species_list)
    image_cases = load_image_cases(args.images, args.image_manifest)
    if not image_cases:
        raise SystemExit("Provide at least one image via --images or --image-manifest.")
    for case in image_cases:
        if not case.path.exists():
            raise SystemExit(f"Image not found: {case.path}")

    device = choose_device(args.device)
    print(f"loading {MODEL_NAME} on {device}", file=sys.stderr)
    model, _, preprocess = open_clip.create_model_and_transforms(MODEL_NAME)
    tokenizer = open_clip.get_tokenizer(MODEL_NAME)
    model.to(device)
    model.eval()

    full_text_matrix = encode_text_matrix(
        model=model,
        tokenizer=tokenizer,
        species=species,
        templates=templates,
        label_text_type=args.label_text_type,
        batch_size=args.batch_size,
        species_batch_size=args.species_batch_size,
        device=device,
    )
    saved_text_matrix = full_text_matrix.astype(args.embedding_dtype)
    embeddings_path = output_dir / "biocap_text_embeddings.npz"
    np.savez_compressed(
        embeddings_path,
        embeddings=saved_text_matrix,
        scientific_names=np.asarray([item.scientific_name for item in species]),
        common_names=np.asarray([item.common_name for item in species]),
        taxa=np.asarray([item.taxon for item in species]),
        prompt_templates=np.asarray(templates),
        label_text_type=np.asarray([args.label_text_type]),
        prompt_preset=np.asarray([prompt_preset]),
        model_name=np.asarray([MODEL_NAME]),
    )
    cached_matrix = np.load(embeddings_path)["embeddings"].astype(np.float32)
    cached_matrix /= np.linalg.norm(cached_matrix, axis=1, keepdims=True)

    fresh_text_matrix = full_text_matrix.astype(np.float32)
    fresh_text_matrix /= np.linalg.norm(fresh_text_matrix, axis=1, keepdims=True)

    vision = NormalizedVisionEncoder(model).to(device).eval()
    manual_vision = ManualNormalizedVisionEncoder(model).to(device).eval()
    traced = None
    traced_name = None
    if args.trace_vision or args.export_coreml:
        disable_torch_fused_attention_for_export()
        trace_source = manual_vision if args.coreml_export_path == "manual" else vision
        traced_name = args.coreml_export_path
        example = torch.zeros(1, 3, 224, 224, dtype=torch.float32, device=device)
        with torch.inference_mode():
            traced = torch.jit.trace(trace_source, example)
        traced_path = output_dir / f"biocap_vision_encoder_{traced_name}_traced.pt"
        traced.save(str(traced_path))

    rows: list[dict[str, object]] = []
    report: dict[str, object] = {
        "model": MODEL_NAME,
        "speciesCount": len(species),
        "promptTemplates": templates,
        "promptPreset": prompt_preset,
        "labelTextType": args.label_text_type,
        "embeddingPath": str(embeddings_path),
        "topK": args.top_k,
        "tolerance": args.tolerance,
        "images": [],
    }

    max_similarity_delta = 0.0
    max_vision_delta = 0.0
    max_manual_vision_delta = 0.0
    max_traced_delta = 0.0
    topk_mismatches = 0
    coreml_delta = None

    for case in image_cases:
        image_feature = encode_image(model, preprocess, case.path, device)
        vision_feature = encode_image_with_vision_tower(vision, preprocess, case.path, device)
        vision_delta = float(torch.max(torch.abs(image_feature - vision_feature)).item())
        max_vision_delta = max(max_vision_delta, vision_delta)
        manual_vision_feature = encode_image_with_vision_tower(
            manual_vision, preprocess, case.path, device
        )
        manual_vision_delta = float(
            torch.max(torch.abs(image_feature - manual_vision_feature)).item()
        )
        max_manual_vision_delta = max(max_manual_vision_delta, manual_vision_delta)

        traced_delta = None
        if traced is not None:
            image = Image.open(case.path).convert("RGB")
            tensor = preprocess(image).unsqueeze(0).to(device)
            with torch.inference_mode():
                traced_feature = traced(tensor).cpu()[0]
            traced_delta = float(torch.max(torch.abs(image_feature - traced_feature)).item())
            max_traced_delta = max(max_traced_delta, traced_delta)

        full_scores = image_feature.numpy() @ fresh_text_matrix.T
        cached_scores = image_feature.numpy() @ cached_matrix.T
        similarity_delta = float(np.max(np.abs(full_scores - cached_scores)))
        max_similarity_delta = max(max_similarity_delta, similarity_delta)

        full_topk = topk(full_scores, species, args.top_k)
        cached_topk = topk(cached_scores, species, args.top_k)
        same_topk = [row["scientificName"] for row in full_topk] == [
            row["scientificName"] for row in cached_topk
        ]
        if not same_topk:
            topk_mismatches += 1

        expected_full_rank = expected_rank(
            full_scores, species, case.expected_scientific_name
        )
        expected_cached_rank = expected_rank(
            cached_scores, species, case.expected_scientific_name
        )

        image_report = {
            "path": str(case.path),
            "expectedScientificName": case.expected_scientific_name,
            "fullTopK": full_topk,
            "cachedTopK": cached_topk,
            "sameTopK": same_topk,
            "expectedFullRank": expected_full_rank,
            "expectedCachedRank": expected_cached_rank,
            "maxSimilarityDelta": similarity_delta,
            "visionDelta": vision_delta,
            "manualVisionDelta": manual_vision_delta,
            "tracedDelta": traced_delta,
        }
        report["images"].append(image_report)

        rows.append(
            {
                "image": str(case.path),
                "expectedScientificName": case.expected_scientific_name or "",
                "fullTop1": full_topk[0]["scientificName"],
                "cachedTop1": cached_topk[0]["scientificName"],
                "sameTopK": same_topk,
                "expectedFullRank": expected_full_rank or "",
                "expectedCachedRank": expected_cached_rank or "",
                "maxSimilarityDelta": similarity_delta,
                "visionDelta": vision_delta,
                "manualVisionDelta": manual_vision_delta,
                "tracedDelta": traced_delta if traced_delta is not None else "",
            }
        )

    if args.export_coreml:
        if traced is None:
            raise AssertionError("traced model should exist when exporting Core ML")
        example = torch.zeros(1, 3, 224, 224, dtype=torch.float32, device=device)
        with torch.inference_mode():
            pytorch_output = traced(example).cpu()
        coreml_delta = compare_coreml(args.export_coreml, traced.cpu(), example.cpu(), pytorch_output)

    report["summary"] = {
        "maxSimilarityDelta": max_similarity_delta,
        "maxVisionDelta": max_vision_delta,
        "maxManualVisionDelta": max_manual_vision_delta,
        "maxTracedDelta": max_traced_delta if traced is not None else None,
        "coreMLDelta": coreml_delta,
        "topKMismatches": topk_mismatches,
        "passed": (
            max_similarity_delta <= args.tolerance
            and max_vision_delta <= args.tolerance
            and max_manual_vision_delta <= args.tolerance
            and topk_mismatches == 0
            and (traced is None or max_traced_delta <= args.tolerance)
            and (coreml_delta is None or coreml_delta <= 5e-3)
        ),
    }
    (output_dir / "parity_report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    write_csv(output_dir / "rankings.csv", rows)

    summary = report["summary"]
    print(json.dumps(summary, indent=2, sort_keys=True))
    if not summary["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
