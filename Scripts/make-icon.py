#!/usr/bin/env python3
"""Draw the app icon from the palette, so it can't drift from the app.

    pip install pillow
    python3 Scripts/make-icon.py

Writes LiftLog/Assets.xcassets/AppIcon.appiconset/icon-1024.png.

The mark is the same barbell as `Barbell` in Theme.swift — bar running past two
plates a side, outer plate shorter — and ACCENT below is Theme.accent. Re-skin
the app and re-run this, rather than editing a PNG by hand.
"""
from PIL import Image, ImageDraw

OUT = "LiftLog/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
SIZE, SUPERSAMPLE = 1024, 4

# Steel, a touch either side of Theme.accent (#1F7899) for depth.
TOP    = (45, 149, 186)   # #2D95BA
BOTTOM = (20, 96, 124)    # #14607C
MARK   = (232, 239, 243)  # #E8EFF3 — brushed off-white, faint cool cast

# x0, y0, x1, y1, corner radius, on a 1024 grid. The mark spans ~80% of the
# width: any wider and its corners start meeting iOS's squircle mask.
PARTS = [
    (102, 485, 921, 539, 27),   # the bar
    (135, 420, 189, 604, 15),   # outer plate, left
    (221, 334, 275, 690, 15),   # inner plate, left
    (749, 334, 803, 690, 15),   # inner plate, right
    (835, 420, 889, 604, 15),   # outer plate, right
]


def main() -> None:
    w = SIZE * SUPERSAMPLE
    img = Image.new("RGB", (w, w), TOP)
    draw = ImageDraw.Draw(img)

    # One line per row at full supersampled height, so the gradient doesn't band.
    for y in range(w):
        t = y / (w - 1)
        draw.line([(0, y), (w, y)],
                  fill=tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))

    for x0, y0, x1, y1, r in PARTS:
        draw.rounded_rectangle([x0 * SUPERSAMPLE, y0 * SUPERSAMPLE,
                                x1 * SUPERSAMPLE, y1 * SUPERSAMPLE],
                               radius=r * SUPERSAMPLE, fill=MARK)

    # Downsample for the anti-aliasing, and full-bleed: iOS masks the corners
    # itself. RGB, never RGBA — an iOS app icon must carry no alpha channel.
    img.resize((SIZE, SIZE), Image.LANCZOS).save(OUT, "PNG", optimize=True)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
