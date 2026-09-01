"""Generate staged synthetic clay fixtures and labeled non-destructive retry variants."""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


def make_fixture(path: Path, base: tuple[int, int, int], highlight: tuple[int, int, int], label: str, variant: int = 0) -> None:
    size = (900, 600)
    image = Image.new("RGB", size, (224, 220, 210))
    draw = ImageDraw.Draw(image)
    # Neutral tabletop, angled card, and soft shadows make the fake staged context explicit.
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.ellipse((125, 345, 770, 520), fill=(48, 38, 30, 82 + 20 * variant))
    image = Image.alpha_composite(image.convert("RGBA"), shadow.filter(ImageFilter.GaussianBlur(26)))
    clay = Image.new("RGBA", size, (0, 0, 0, 0))
    clay_draw = ImageDraw.Draw(clay)
    rendered_base = tuple(max(0, channel - 10 * variant) for channel in base)
    rendered_highlight = tuple(min(255, channel + 18 * variant) for channel in highlight)
    # Irregular tapered clay coil, curved and asymmetrical rather than a geometric capsule.
    spine = [(180, 385), (235, 325), (310, 290), (395, 305), (455, 365), (535, 385), (630, 350), (715, 280)]
    widths = [80 + 8 * variant, 95 + 9 * variant, 108 + 10 * variant, 93 + 8 * variant, 78 + 7 * variant, 66 + 6 * variant, 51 + 4 * variant, 30 + 2 * variant]
    for (x, y), width in zip(spine, widths):
        clay_draw.ellipse((x - width, y - width * .62, x + width, y + width * .62), fill=rendered_base + (255,), outline=(63, 47, 36, 255), width=7 + variant)
    for left, right, width in zip(spine, spine[1:], widths[1:]):
        clay_draw.line((left, right), fill=rendered_base + (255,), width=int(width * 1.22))
    clay_draw.line(spine, fill=(70, 50, 37, 255), width=7)
    clay_draw.line([(205, 350), (300, 300), (390, 320), (450, 370), (525, 380), (610, 345)], fill=rendered_highlight + (220,), width=22 + 4 * variant)
    clay_draw.arc((230, 240, 530, 435), 155, 300, fill=(246, 211, 170, 165), width=11)
    image = Image.alpha_composite(image, clay.filter(ImageFilter.GaussianBlur(1)))
    draw = ImageDraw.Draw(image)
    title_font = ImageFont.load_default(size=24)
    body_font = ImageFont.load_default(size=18)
    watermark_font = ImageFont.load_default(size=52)
    draw.rounded_rectangle((25, 20, 875, 103), radius=8, fill=(250, 250, 247, 238), outline=(30, 30, 30), width=3)
    retry_label = f" | RETRY VARIANT {variant}" if variant else ""
    draw.text((48, 34), f"SYNTHETIC | STAGED CLAY PROP | {label}{retry_label}", fill=(10, 10, 10), font=title_font)
    draw.text((48, 68), "Offline vision test fixture; not a patient image", fill=(10, 10, 10), font=body_font)
    # Prominent diagonal watermark remains visible over the image content.
    draw.text((282, 305), "SYNTHETIC", fill=(255, 255, 255, 235), stroke_width=3, stroke_fill=(20, 20, 20), font=watermark_font)
    draw.text((30, 550), "Staged clay prop for offline model testing; not a patient image.", fill=(35, 35, 35), font=body_font)
    image.convert("RGB").save(path, "PNG", optimize=True)


def make_pair(target: Path, variant: int = 0) -> tuple[Path, Path]:
    if variant not in {0, 1, 2}:
        raise ValueError("fixture variant must be 0, 1, or 2")
    target.mkdir(parents=True, exist_ok=True)
    brown = target / "synthetic_brown_clay_prop.png"
    green = target / "synthetic_green_clay_prop.png"
    make_fixture(brown, (126, 76, 39), (199, 139, 84), "BROWN CLAY PROP", variant)
    make_fixture(green, (57, 115, 57), (131, 178, 91), "GREEN CLAY PROP", variant)
    return brown, green


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir")
    parser.add_argument("--variant", type=int, default=0, choices=(0, 1, 2))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    target = Path(args.output_dir).resolve() if args.output_dir else root / "data" / "demo"
    if args.variant and root / "data" / "demo" == target:
        raise SystemExit("retry variants must not overwrite committed fixtures; choose --output-dir")
    if root not in target.parents:
        raise SystemExit("fixture output must remain inside the workspace")
    make_pair(target, args.variant)


if __name__ == "__main__":
    main()
