from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageEnhance, ImageOps


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts" / "visual-validation"
TARGET_DIR = (
    ROOT
    / ".codex-remote-attachments"
    / "019f513f-9e70-7272-92e9-b3895c11fe59"
    / "73273fab-cd81-4f42-a0d9-68a368adc494"
)
CANONICAL = (768, 1536)


CASES = {
    "welcome": {
        "target": TARGET_DIR / "2-Photo-2.jpg",
        "current": ROOT / "test" / "goldens" / "visual_welcome_640.png",
    },
    "restore": {
        "target": TARGET_DIR / "1-Photo-1.jpg",
        "current": ROOT / "test" / "goldens" / "visual_restore_26_640.png",
    },
}


def _resize_to_canonical(image: Image.Image) -> Image.Image:
    if image.size == CANONICAL:
        return image
    return image.resize(CANONICAL, Image.Resampling.LANCZOS)


def _normalize_current(image: Image.Image) -> Image.Image:
    if image.height != CANONICAL[1]:
        image = image.resize((image.width, CANONICAL[1]), Image.Resampling.LANCZOS)
    if image.width == 769:
        left = (image.width - CANONICAL[0]) // 2
        image = image.crop((left, 0, left + CANONICAL[0], CANONICAL[1]))
    elif image.width != CANONICAL[0]:
        image = image.resize(CANONICAL, Image.Resampling.LANCZOS)
    return image


def _normalize_target(name: str, image: Image.Image) -> Image.Image:
    # The provided files in this environment are downsampled JPEG references.
    # If a full-height restore target is supplied later, this preserves the
    # requested horizontal-only normalization.
    if name == "restore" and image.height == CANONICAL[1]:
        if image.width != CANONICAL[0]:
            image = image.resize((CANONICAL[0], image.height), Image.Resampling.LANCZOS)
        return image
    return _resize_to_canonical(image)


def _metrics(target: Image.Image, current: Image.Image) -> dict[str, float]:
    diff = ImageChops.difference(target, current).convert("RGB")
    pixels = list(diff.getdata())
    samples = len(pixels) * 3
    total_abs = sum(channel for pixel in pixels for channel in pixel)
    total_sq = sum(channel * channel for pixel in pixels for channel in pixel)
    return {
        "mae": round(total_abs / samples, 4),
        "rmse": round(math.sqrt(total_sq / samples), 4),
        "max_channel_diff": max(channel for pixel in pixels for channel in pixel),
    }


def _write_artifacts(name: str, target: Image.Image, current: Image.Image) -> dict[str, float]:
    target_path = OUT / f"normalized-target-{name}.png"
    current_path = OUT / f"normalized-current-{name}.png"
    side_path = OUT / f"side-by-side-{name}.png"
    overlay_path = OUT / f"alpha-overlay-{name}.png"
    heatmap_path = OUT / f"absolute-diff-heatmap-{name}.png"

    target.save(target_path)
    current.save(current_path)

    side = Image.new("RGB", (CANONICAL[0] * 2, CANONICAL[1]), (0, 0, 0))
    side.paste(target, (0, 0))
    side.paste(current, (CANONICAL[0], 0))
    side.save(side_path)

    Image.blend(target, current, 0.5).save(overlay_path)

    diff = ImageChops.difference(target, current).convert("L")
    diff = ImageEnhance.Contrast(ImageOps.autocontrast(diff)).enhance(1.8)
    heatmap = ImageOps.colorize(diff, black="#00120c", white="#ff3b30", mid="#ffd166")
    heatmap.save(heatmap_path)

    result = _metrics(target, current)
    result.update(
        {
            "target": str(target_path.relative_to(ROOT)),
            "current": str(current_path.relative_to(ROOT)),
            "side_by_side": str(side_path.relative_to(ROOT)),
            "alpha_overlay": str(overlay_path.relative_to(ROOT)),
            "heatmap": str(heatmap_path.relative_to(ROOT)),
        }
    )
    return result


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    all_metrics: dict[str, dict[str, float]] = {}
    for name, paths in CASES.items():
        target_src = paths["target"]
        current_src = paths["current"]
        if not target_src.exists():
            raise FileNotFoundError(target_src)
        if not current_src.exists():
            raise FileNotFoundError(current_src)

        target_raw = Image.open(target_src).convert("RGB")
        current_raw = Image.open(current_src).convert("RGB")
        target = _normalize_target(name, target_raw)
        current = _normalize_current(current_raw)
        all_metrics[name] = _write_artifacts(name, target, current)

    metrics_path = OUT / "metrics.json"
    metrics_path.write_text(json.dumps(all_metrics, indent=2), encoding="utf-8")
    print(json.dumps(all_metrics, indent=2))


if __name__ == "__main__":
    main()
