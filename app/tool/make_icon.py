"""Draw Tanim's launcher icon: a rice leaf with a lesion inside scan brackets.

Usage (from app/):
    ../.venv/Scripts/python tool/make_icon.py
    dart run flutter_launcher_icons

Writes assets/icon/icon.png (full icon, iOS and legacy Android) and
assets/icon/foreground.png (transparent, for Android adaptive icons).
"""

from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
SS = 4  # draw big, then shrink, for smooth edges
GREEN = (47, 110, 43)
LEAF = (196, 232, 160)
VEIN = (120, 178, 92)
SPOT = (150, 92, 40)
HALO = (232, 205, 110)
WHITE = (255, 255, 255)
OUT = Path(__file__).resolve().parents[1] / "assets" / "icon"


def draw_foreground(scale: float) -> Image.Image:
    """Leaf + brackets centred on a transparent square. scale shrinks the art for the adaptive safe zone."""
    n = SIZE * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = n / 2

    def p(x: float, y: float) -> tuple[float, float]:
        return (c + (x - 0.5) * n * scale, c + (y - 0.5) * n * scale)

    # Scan brackets.
    w = n * scale * 0.035
    for (x, y, dx, dy) in [(0.14, 0.14, 1, 1), (0.86, 0.14, -1, 1), (0.14, 0.86, 1, -1), (0.86, 0.86, -1, -1)]:
        d.line([p(x, y + dy * 0.16), p(x, y), p(x + dx * 0.16, y)], fill=WHITE, width=round(w), joint="curve")

    # A long, slightly curved leaf blade from bottom-left to top-right.
    top, bottom = [], []
    steps = 60
    for i in range(steps + 1):
        t = i / steps
        x = 0.24 + 0.54 * t
        y = 0.78 - 0.56 * t - 0.06 * (4 * t * (1 - t))
        half = 0.085 * (4 * t * (1 - t)) ** 0.7
        top.append(p(x - half * 0.7, y - half * 0.7))
        bottom.append(p(x + half * 0.7, y + half * 0.7))
    d.polygon(top + bottom[::-1], fill=LEAF)
    mid = [p(0.24 + 0.54 * t, 0.78 - 0.56 * t - 0.06 * (4 * t * (1 - t))) for t in [i / steps for i in range(steps + 1)]]
    d.line(mid[4:-4], fill=VEIN, width=round(w * 0.35))

    # A brown-spot lesion with a yellow halo.
    sx, sy = p(0.55, 0.47)
    for r, col in [(0.065, HALO), (0.04, SPOT)]:
        rr = r * n * scale
        d.ellipse([sx - rr, sy - rr * 0.75, sx + rr, sy + rr * 0.75], fill=col)
    return img.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    full = Image.new("RGBA", (SIZE, SIZE), GREEN + (255,))
    full.alpha_composite(draw_foreground(0.82))
    full.convert("RGB").save(OUT / "icon.png")
    # Adaptive icons crop to a circle/squircle: keep the art inside the middle ~66%.
    draw_foreground(0.62).save(OUT / "foreground.png")
    print(f"Wrote {OUT / 'icon.png'} and {OUT / 'foreground.png'}")


if __name__ == "__main__":
    main()
