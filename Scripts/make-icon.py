#!/usr/bin/env python3
"""Draw the app icon from the palette, so it can't drift from the app.

    pip install pillow
    python3 Scripts/make-icon.py

Writes LiftLog/Assets.xcassets/AppIcon.appiconset/icon-1024.png, and
icon-1024-dark.png for iOS's dark home screen: true black with a hairline
edge, the same mark.

The mark is the same barbell as `Barbell` in Theme.swift — bar running past two
plates a side, outer plate shorter — and ACCENT below is Theme.accent. Re-skin
the app and re-run this, rather than editing a PNG by hand.
"""
from PIL import Image, ImageDraw

OUT = "LiftLog/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
OUT_DARK = "LiftLog/Assets.xcassets/AppIcon.appiconset/icon-1024-dark.png"
SIZE, SUPERSAMPLE = 1024, 4

# Steel, a touch either side of Theme.accent (#1F7899) for depth.
TOP    = (45, 149, 186)   # #2D95BA
BOTTOM = (20, 96, 124)    # #14607C
MARK   = (232, 239, 243)  # #E8EFF3 — brushed off-white, faint cool cast

# Dark: black ground, the edge a quiet grey just inside iOS's mask.
DARK_GROUND = (0, 0, 0)
DARK_EDGE   = (84, 88, 92)    # #54585C
EDGE_INSET, EDGE_WIDTH, EDGE_RADIUS = 30, 9, 200

# x0, y0, x1, y1, corner radius, on a 1024 grid. The mark spans ~80% of the
# width: any wider and its corners start meeting iOS's squircle mask.
PARTS = [
    (102, 485, 921, 539, 27),   # the bar
    (135, 420, 189, 604, 15),   # outer plate, left
    (221, 334, 275, 690, 15),   # inner plate, left
    (749, 334, 803, 690, 15),   # inner plate, right
    (835, 420, 889, 604, 15),   # outer plate, right
]


def draw_mark(draw: ImageDraw.ImageDraw) -> None:
    for x0, y0, x1, y1, r in PARTS:
        draw.rounded_rectangle([x0 * SUPERSAMPLE, y0 * SUPERSAMPLE,
                                x1 * SUPERSAMPLE, y1 * SUPERSAMPLE],
                               radius=r * SUPERSAMPLE, fill=MARK)


def save(img: Image.Image, path: str) -> None:
    # Downsample for the anti-aliasing, and full-bleed: iOS masks the corners
    # itself. RGB, never RGBA — an iOS app icon must carry no alpha channel.
    img.resize((SIZE, SIZE), Image.LANCZOS).save(path, "PNG", optimize=True)
    print(f"wrote {path}")


def main() -> None:
    w = SIZE * SUPERSAMPLE
    img = Image.new("RGB", (w, w), TOP)
    draw = ImageDraw.Draw(img)

    # One line per row at full supersampled height, so the gradient doesn't band.
    for y in range(w):
        t = y / (w - 1)
        draw.line([(0, y), (w, y)],
                  fill=tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))
    draw_mark(draw)
    save(img, OUT)

    dark = Image.new("RGB", (w, w), DARK_GROUND)
    draw = ImageDraw.Draw(dark)
    i, e = EDGE_INSET * SUPERSAMPLE, EDGE_WIDTH * SUPERSAMPLE
    draw.rounded_rectangle([i, i, w - i, w - i], radius=EDGE_RADIUS * SUPERSAMPLE,
                           outline=DARK_EDGE, width=e)
    draw_mark(draw)
    save(dark, OUT_DARK)


if __name__ == "__main__":
    main()
