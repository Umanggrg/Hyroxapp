"""
§31 Volt rebrand — App Icon generator.

Renders three 1024x1024 PNGs (Dark / Light / Tinted) matching the
BrandTriangle shape from SignInView.swift, so the icon visually
matches the splash + onboarding triangle.

Triangle geometry (from BrandTriangle.path(in:)):
  Mountain-up isoceles triangle, peak at top-center, base at bottom.
  Apex inset slightly from the top edge so it doesn't bleed.
  Base inset slightly from the bottom edge.

For a 1024-square canvas at iOS App Icon proportions, we draw the
triangle at ~62% of the canvas width, centered, with breathing room
around it. iOS will round the corners on render; we just produce
a square fill.

Colors per variant:
  • Dark   — bg #0A0A0B (Trakrr near-black), triangle #D4FF00 (Volt)
  • Light  — bg #F5F5F0 (warm off-white), triangle #0A0A0B (near-black);
             Light mode is rare for app icon contexts (iOS 18 keeps
             a single bg per appearance) but we render it so the
             auto-light home screen still looks intentional.
  • Tinted — grayscale silhouette per Apple's iOS 18 tinted-icon
             spec. White triangle on near-black bg; iOS applies the
             user's chosen tint over the silhouette.
"""

from PIL import Image, ImageDraw

CANVAS = 1024
TRIANGLE_WIDTH_FRACTION = 0.62  # ~62% of canvas width
TRIANGLE_HEIGHT_FRACTION = 0.56  # slightly shorter than equilateral for visual balance


def triangle_points(canvas_size: int) -> list[tuple[int, int]]:
    """
    Mountain-up triangle vertices on a square canvas.
    Same proportions as BrandTriangle.path(in:) in SignInView.swift.
    Centered horizontally, vertically nudged slightly above middle
    so optical center matches geometric center.
    """
    w = canvas_size * TRIANGLE_WIDTH_FRACTION
    h = canvas_size * TRIANGLE_HEIGHT_FRACTION

    # Vertical center of the triangle's bounding box, nudged 2% up
    # so the optical weight (which is bottom-heavy in a triangle)
    # sits at the canvas center.
    center_x = canvas_size / 2
    center_y = canvas_size / 2 - canvas_size * 0.02

    apex_x = center_x
    apex_y = center_y - h / 2

    base_left_x = center_x - w / 2
    base_y = center_y + h / 2

    base_right_x = center_x + w / 2

    return [
        (int(apex_x), int(apex_y)),
        (int(base_left_x), int(base_y)),
        (int(base_right_x), int(base_y)),
    ]


def render_icon(bg_hex: str, triangle_hex: str, out_path: str) -> None:
    """Render a single 1024x1024 icon PNG."""
    bg = tuple(int(bg_hex[i:i+2], 16) for i in (0, 2, 4))
    fg = tuple(int(triangle_hex[i:i+2], 16) for i in (0, 2, 4))

    img = Image.new("RGB", (CANVAS, CANVAS), bg)
    draw = ImageDraw.Draw(img)
    points = triangle_points(CANVAS)
    draw.polygon(points, fill=fg)
    img.save(out_path, "PNG", optimize=True)
    print(f"  wrote {out_path}")


def main() -> None:
    print("Generating Trakrr Volt-lime app icons (§31 rebrand)...")

    # Dark appearance — Volt lime triangle on Trakrr near-black.
    # This is the canonical brand-on-brand look. Most iOS users
    # default to the dark home screen appearance now.
    render_icon(
        bg_hex="0A0A0B",
        triangle_hex="D4FF00",
        out_path="AppIcon-Dark.png",
    )

    # Light appearance — dark triangle on warm off-white. Apple
    # auto-switches to this when the user picks light-mode home
    # screen. Inverts the brand-on-brand relationship; the
    # triangle stays the focal point.
    render_icon(
        bg_hex="F5F5F0",
        triangle_hex="0A0A0B",
        out_path="AppIcon-Light.png",
    )

    # Tinted appearance — iOS 18 spec. iOS applies the user's
    # chosen tint over a grayscale silhouette. We render a
    # white-on-black icon so the user's tint sits on the
    # triangle (the brand element), not the background.
    render_icon(
        bg_hex="000000",
        triangle_hex="FFFFFF",
        out_path="AppIcon-Tinted.png",
    )

    print("Done. Three 1024x1024 PNGs ready.")


if __name__ == "__main__":
    main()
