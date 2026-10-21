#!/usr/bin/env python3
"""Draw the app icon from the palette, so it can't drift from the app.

    pip install pillow
    python3 Scripts/make-icon.py

Writes LiftLog/Assets.xcassets/AppIcon.appiconset/icon-1024.png (a
terracotta barbell on ivory) and icon-1024-dark.png for iOS's dark home
screen (the same mark, lifted a touch, on warm charcoal): the app's own
grounds and accent.

The mark is the same barbell as `Barbell` in Brand.swift — bar running past two
plates a side, outer plate shorter — and the colours are Theme's. Re-skin the
app and re-run this, rather than editing a PNG by hand.
"""
from PIL import Image, ImageDraw

OUT = "LiftLog/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
OUT_DARK = "LiftLog/Assets.xcassets/AppIcon.appiconset/icon-1024-dark.png"
SIZE, SUPERSAMPLE = 1024, 4

IVORY     = (250, 249, 245)   # #FAF9F5 — Theme.ground, light
CHARCOAL  = (38, 38, 36)      # #262624 — Theme.ground, dark
ACCENT    = (198, 97, 63)     # #C6613F — Brand.accent
ACCENT_LIT = (217, 119, 87)   # #D97757 — the accent lifted for the dark ground

# x0, y0, x1, y1, corner radius, on a 1024 grid. The mark spans ~80% of the
# width: any wider and its corners start meeting iOS's squircle mask.
PARTS = [
    (102, 485, 921, 539, 27),   # the bar
    (135, 420, 189, 604, 15),   # outer plate, left
    (221, 334, 275, 690, 15),   # inner plate, left
    (749, 334, 803, 690, 15),   # inner plate, right
    (835, 420, 889, 604, 15),   # outer plate, right
]


def draw_mark(draw: ImageDraw.ImageDraw, colour) -> None:
    for x0, y0, x1, y1, r in PARTS:
        draw.rounded_rectangle([x0 * SUPERSAMPLE, y0 * SUPERSAMPLE,
                                x1 * SUPERSAMPLE, y1 * SUPERSAMPLE],
                               radius=r * SUPERSAMPLE, fill=colour)


def save(img: Image.Image, path: str) -> None:
    # Downsample for the anti-aliasing, and full-bleed: iOS masks the corners
    # itself. RGB, never RGBA — an iOS app icon must carry no alpha channel.
    img.resize((SIZE, SIZE), Image.LANCZOS).save(path, "PNG", optimize=True)
    print(f"wrote {path}")


def main() -> None:
    w = SIZE * SUPERSAMPLE
    for ground, mark, path in [(IVORY, ACCENT, OUT), (CHARCOAL, ACCENT_LIT, OUT_DARK)]:
        img = Image.new("RGB", (w, w), ground)
        draw_mark(ImageDraw.Draw(img), mark)
        save(img, path)


if __name__ == "__main__":
    main()
