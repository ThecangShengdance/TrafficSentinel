#!/usr/bin/env python3
"""Generate the TrafficSentinel app icon.

Draws a 1024 pt macOS icon (blue → cyan gradient squircle with white
download/upload arrows, a thin timer ring and a rose quota arc) at 4×
supersampling, then writes every size needed by an Xcode asset catalog
into Sources/Assets.xcassets/AppIcon.appiconset.

Requires Python 3 with Pillow and numpy:

    python3 scripts/make_icon.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Sources" / "Assets.xcassets" / "AppIcon.appiconset"

SCALE = 4                 # supersampling factor
BASE = 1024               # logical icon size
CANVAS = BASE * SCALE     # 4096 px working canvas


def px(value: float) -> float:
    """Convert a 1024-grid coordinate to the supersampled canvas."""
    return value * SCALE


def gradient_square() -> Image.Image:
    """Rounded-square background filled with a diagonal blue→cyan gradient."""
    # Build the gradient at 1024² and upscale; it is perfectly smooth anyway.
    y, x = np.mgrid[0:BASE, 0:BASE].astype(np.float32)
    t = 0.62 * (x / (BASE - 1)) + 0.38 * (y / (BASE - 1))

    stops = np.array([0.0, 0.52, 1.0], dtype=np.float32)
    colors = np.array(
        [
            [24, 63, 168],    # deep indigo-blue
            [29, 112, 232],   # vivid blue
            [6, 178, 205],    # cyan
        ],
        dtype=np.float32,
    )
    rgb = np.stack(
        [np.interp(t, stops, colors[:, c]) for c in range(3)], axis=-1
    )

    # Soft light from the top-left corner.
    dx = x / (BASE - 1) - 0.18
    dy = y / (BASE - 1) - 0.08
    highlight = np.exp(-(dx * dx + dy * dy) / 0.16)[..., None]
    rgb = rgb + highlight * 34.0

    # Gentle darkening toward the bottom-right keeps the glyph readable.
    dx2 = x / (BASE - 1) - 0.85
    dy2 = y / (BASE - 1) - 0.9
    vignette = np.exp(-(dx2 * dx2 + dy2 * dy2) / 0.22)[..., None]
    rgb = rgb - vignette * 26.0

    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    img = Image.fromarray(rgb, "RGB").resize((CANVAS, CANVAS), Image.LANCZOS)

    # Squircle mask: Apple's 824/1024 grid with a 100 pt margin.
    mask = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (px(100), px(100), px(924), px(924)),
        radius=px(185),
        fill=255,
    )
    out = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)

    draw = ImageDraw.Draw(out)
    # Hairline inner rim for a crisp edge on light backgrounds.
    draw.rounded_rectangle(
        (px(103), px(103), px(921), px(921)),
        radius=px(182),
        outline=(255, 255, 255, 52),
        width=max(1, int(px(2.4))),
    )
    return out


def rounded_cap(draw: ImageDraw.ImageDraw, xy: tuple[float, float], r: float, fill):
    x, y = xy
    draw.ellipse((x - r, y - r, x + r, y + r), fill=fill)


def draw_gauge(img: Image.Image) -> None:
    """Draw a pair of bold traffic arrows (down + up) on the gradient."""
    draw = ImageDraw.Draw(img)

    white = (255, 255, 255, 255)

    # Download arrow (left): shaft with a wide triangular head.
    shaft_w = px(62)
    x = px(402)
    draw.rounded_rectangle(
        (x - shaft_w / 2, px(332), x + shaft_w / 2, px(596)),
        radius=px(31),
        fill=white,
    )
    draw.polygon(
        [
            (px(300), px(566)),
            (px(504), px(566)),
            (px(402), px(706)),
        ],
        fill=white,
    )

    # Upload arrow (right), mirrored.
    x2 = px(622)
    draw.rounded_rectangle(
        (x2 - shaft_w / 2, px(428), x2 + shaft_w / 2, px(692)),
        radius=px(31),
        fill=white,
    )
    draw.polygon(
        [
            (px(520), px(458)),
            (px(724), px(458)),
            (px(622), px(318)),
        ],
        fill=white,
    )

    # A faint timer ring frames the arrows; the rose segment is the part of
    # the quota already spent.
    radius = px(356)
    cx, cy = px(512), px(512)
    box = (cx - radius, cy - radius, cx + radius, cy + radius)
    ring_w = int(px(16))
    draw.ellipse(box, outline=(255, 255, 255, 34), width=ring_w)
    draw.arc(
        box,
        start=-102,
        end=-42,
        fill=(255, 111, 140, 255),
        width=ring_w,
    )


def add_shadow(icon: Image.Image) -> Image.Image:
    """Bake a soft drop shadow under the squircle for Finder/Dock depth."""
    pad = 48
    canvas = Image.new("RGBA", (icon.width + pad * 2, icon.height + pad * 2), (0, 0, 0, 0))
    alpha = icon.split()[3]
    shadow = Image.new("RGBA", icon.size, (4, 12, 30, 0))
    shadow.putalpha(alpha.point(lambda a: int(a * 0.34)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    canvas.alpha_composite(shadow, (pad, pad + 10))
    canvas.alpha_composite(icon, (pad, pad))
    return canvas


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    icon = gradient_square()
    draw_gauge(icon)
    icon = icon.resize((BASE, BASE), Image.LANCZOS)
    icon = add_shadow(icon)

    # Trim back to a 1024 canvas with the icon centered, keeping a little air.
    master = icon.resize((BASE, BASE), Image.LANCZOS)
    master.save(ROOT / "docs" / "icon.png")

    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    for size, name in sizes:
        master.resize((size, size), Image.LANCZOS).save(OUT / name, optimize=True)

    contents = {
        "images": [
            {"filename": "icon_16x16.png", "idiom": "mac", "scale": "1x", "size": "16x16"},
            {"filename": "icon_16x16@2x.png", "idiom": "mac", "scale": "2x", "size": "16x16"},
            {"filename": "icon_32x32.png", "idiom": "mac", "scale": "1x", "size": "32x32"},
            {"filename": "icon_32x32@2x.png", "idiom": "mac", "scale": "2x", "size": "32x32"},
            {"filename": "icon_128x128.png", "idiom": "mac", "scale": "1x", "size": "128x128"},
            {"filename": "icon_128x128@2x.png", "idiom": "mac", "scale": "2x", "size": "128x128"},
            {"filename": "icon_256x256.png", "idiom": "mac", "scale": "1x", "size": "256x256"},
            {"filename": "icon_256x256@2x.png", "idiom": "mac", "scale": "2x", "size": "256x256"},
            {"filename": "icon_512x512.png", "idiom": "mac", "scale": "1x", "size": "512x512"},
            {"filename": "icon_512x512@2x.png", "idiom": "mac", "scale": "2x", "size": "512x512"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (OUT / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")

    (ROOT / "Sources" / "Assets.xcassets" / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )

    print(f"wrote {len(sizes)} icon sizes to {OUT}")
    print(f"preview: {ROOT / 'docs' / 'icon.png'}")


if __name__ == "__main__":
    main()
