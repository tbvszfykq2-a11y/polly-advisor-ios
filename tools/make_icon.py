#!/usr/bin/env python3
"""Generate the Polly Advisor app icon and colour assets.

Design intent: a bold ascending sparkline on a near-black instrument panel.
The stroke is built as a single alpha mask and then filled with one smooth
gradient, so there are no seams or banding at the joints. Sized to survive a
40pt home-screen render: thick stroke, generous safe area, no micro-detail.
"""
import json
import math
import pathlib
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Sources" / "PollyAdvisor" / "Assets.xcassets"

S = 2048          # supersampled canvas
OUT = 1024        # final icon edge

MINT = (54, 232, 175)
CYAN = (94, 205, 226)
BLUE = (91, 157, 255)
BG_TOP = (14, 20, 27)
BG_BOT = (5, 7, 10)

STROKE = 152      # stroke weight on the 2048 canvas


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def gradient_image(size, colors):
    """Smooth horizontal multi-stop gradient, then stretched vertically."""
    strip = Image.new("RGB", (size, 1))
    px = strip.load()
    stops = len(colors) - 1
    for x in range(size):
        t = x / max(1, size - 1) * stops
        i = min(stops - 1, int(t))
        px[x, 0] = lerp(colors[i], colors[i + 1], t - i)
    return strip.resize((size, size), Image.BILINEAR)


def main() -> None:
    # --- background -------------------------------------------------------
    base = gradient_image(S, [BG_TOP, BG_BOT]).convert("RGBA")

    # Faint radial lift so the panel has depth without noise.
    lift = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(lift).ellipse(
        [S * 0.08, S * 0.12, S * 0.94, S * 0.98], fill=(28, 86, 104, 40)
    )
    base = Image.alpha_composite(base, lift.filter(ImageFilter.GaussianBlur(230)))

    # --- path -------------------------------------------------------------
    # Nudged right for optical centring; still well inside the safe area.
    nodes = [(0.196, 0.715), (0.412, 0.395), (0.585, 0.585), (0.834, 0.265)]
    pts = [(x * S, y * S) for x, y in nodes]

    # --- stroke mask: one pass, round joints, no overlap seams ------------
    mask = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(mask)
    md.line(pts, fill=255, width=STROKE, joint="curve")
    r = STROKE / 2
    for p in pts:
        md.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=255)
    # No bulged end cap: one uniform stroke, round terminals. Guarantees a
    # seamless silhouette at every size.

    # --- glow, derived from the same mask so it tracks the stroke ---------
    glow = mask.filter(ImageFilter.GaussianBlur(72)).point(lambda v: int(v * 0.55))
    glow_tint = gradient_image(S, [MINT, CYAN, BLUE]).convert("RGBA")
    glow_tint.putalpha(glow)
    base = Image.alpha_composite(base, glow_tint)

    # --- gradient fill through the mask ----------------------------------
    fill = gradient_image(S, [MINT, CYAN, BLUE]).convert("RGBA")
    fill.putalpha(mask)
    base = Image.alpha_composite(base, fill)

    # --- vignette under everything else already applied; finish -----------
    vig = Image.new("L", (S, S), 0)
    vd = ImageDraw.Draw(vig)
    cx = cy = S // 2
    max_r = math.hypot(cx, cy)
    for i in range(64):
        rr = max_r * (1 - i / 64)
        vd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=int(150 * (i / 64) ** 1.9))
    vig = vig.filter(ImageFilter.GaussianBlur(110))
    vig = vig.point(lambda v: v)          # keep smooth ramp
    shadow = Image.new("RGBA", (S, S), (2, 3, 5, 255))
    shadow.putalpha(vig)
    # Multiply-ish: keep the mark legible, darken only the far corners.
    corner = shadow.copy()
    corner.putalpha(vig.point(lambda v: max(0, v - 40)))
    base = Image.alpha_composite(base, corner)

    icon = base.convert("RGB").resize((OUT, OUT), Image.LANCZOS)

    # ±2 levels of noise: invisible up close, removes banding rings in the glow.
    rng = random.Random(20240517)
    px = icon.load()
    for y in range(OUT):
        for x in range(OUT):
            r, g, b = px[x, y]
            n = rng.randint(-2, 2)
            px[x, y] = (min(255, max(0, r + n)),
                        min(255, max(0, g + n)),
                        min(255, max(0, b + n)))

    # --- asset catalog ----------------------------------------------------
    appicon = ASSETS / "AppIcon.appiconset"
    appicon.mkdir(parents=True, exist_ok=True)
    icon.save(appicon / "icon-1024.png", "PNG", optimize=True)

    (ASSETS / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )
    (appicon / "Contents.json").write_text(json.dumps({
        "images": [{
            "filename": "icon-1024.png",
            "idiom": "universal",
            "platform": "ios",
            "size": "1024x1024",
        }],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")

    def colorset(name, rgb):
        d = ASSETS / name
        d.mkdir(parents=True, exist_ok=True)
        (d / "Contents.json").write_text(json.dumps({
            "colors": [{
                "color": {
                    "color-space": "srgb",
                    "components": {
                        "red": f"{rgb[0] / 255:.3f}",
                        "green": f"{rgb[1] / 255:.3f}",
                        "blue": f"{rgb[2] / 255:.3f}",
                        "alpha": "1.000",
                    },
                },
                "idiom": "universal",
            }],
            "info": {"author": "xcode", "version": 1},
        }, indent=2) + "\n")

    colorset("LaunchBackground.colorset", (7, 10, 15))
    colorset("AccentColor.colorset", (91, 157, 255))

    # --- previews for QA --------------------------------------------------
    for edge in (120, 60, 40):
        icon.resize((edge, edge), Image.LANCZOS).save(f"/tmp/icon_{edge}.png")

    print(f"icon {OUT}x{OUT} -> {appicon/'icon-1024.png'}")
    print("previews: /tmp/icon_120.png /tmp/icon_60.png /tmp/icon_40.png")


if __name__ == "__main__":
    main()
