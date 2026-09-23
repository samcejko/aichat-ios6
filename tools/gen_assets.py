#!/usr/bin/env python3
"""Generates the app icon and launch images for iOS 6 (run in CI, needs Pillow).

Usage: python3 tools/gen_assets.py Resources
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else "Resources"
os.makedirs(OUT, exist_ok=True)

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
]


_R = getattr(Image, "Resampling", Image)
LANCZOS, NEAREST = _R.LANCZOS, _R.NEAREST


def font(size):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    try:
        return ImageFont.load_default(size)  # Pillow >= 10.1
    except TypeError:
        sys.exit("gen_assets: no TrueType font found (install fonts-dejavu-core)")


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vertical_gradient(size, top, bottom):
    w, h = size
    col = Image.new("RGB", (1, h))
    col.putdata([lerp(top, bottom, y / max(1, h - 1)) for y in range(h)])
    return col.resize((w, h), NEAREST)


def text_size(draw, text, fnt):
    if hasattr(draw, "textbbox"):
        l, t, r, b = draw.textbbox((0, 0), text, font=fnt)
        return r - l, b - t, l, t
    w, h = draw.textsize(text, font=fnt)
    return w, h, 0, 0


def draw_bubble(img, box, fill, tail=True):
    """Rounded speech bubble inside box=(x0,y0,x1,y1)."""
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = box
    r = int((y1 - y0) * 0.28)
    d.rounded_rectangle((x0, y0, x1, y1), radius=r, fill=fill)
    if tail:
        tw = int((x1 - x0) * 0.16)
        th = int((y1 - y0) * 0.22)
        tx = x0 + int((x1 - x0) * 0.22)
        d.polygon([(tx, y1 - r // 2), (tx + tw, y1 - r // 2), (tx, y1 + th)], fill=fill)


_BASE_ICON = None


def base_icon():
    """The 1024 px master icon, drawn once."""
    global _BASE_ICON
    if _BASE_ICON is not None:
        return _BASE_ICON
    base = 1024
    img = vertical_gradient((base, base), (98, 168, 250), (28, 92, 200))
    # subtle gloss on the top half (iOS 6 adds its own shine as well)
    gloss = Image.new("RGBA", (base, base), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gloss)
    gd.rectangle((0, 0, base, base // 2), fill=(255, 255, 255, 28))
    img = Image.alpha_composite(img.convert("RGBA"), gloss)
    # bubble
    margin = int(base * 0.16)
    box = (margin, int(base * 0.20), base - margin, int(base * 0.70))
    draw_bubble(img, box, (255, 255, 255, 255))
    d = ImageDraw.Draw(img)
    fnt = font(int(base * 0.30))
    w, h, l, t = text_size(d, "AI", fnt)
    cx = (box[0] + box[2]) // 2
    cy = (box[1] + box[3]) // 2
    d.text((cx - w // 2 - l, cy - h // 2 - t), "AI", font=fnt, fill=(32, 96, 205, 255))
    _BASE_ICON = img.convert("RGB")
    return _BASE_ICON


def make_icon(size):
    return base_icon().resize((size, size), LANCZOS)


def make_launch(w, h):
    img = vertical_gradient((w, h), (236, 238, 243), (214, 217, 226))
    d = ImageDraw.Draw(img)
    s = int(min(w, h) * 0.18)
    icon = make_icon(s)
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, s - 1, s - 1), radius=int(s * 0.22), fill=255)
    cx, cy = w // 2, int(h * 0.42)
    img.paste(icon, (cx - s // 2, cy - s // 2), mask)
    fnt = font(int(min(w, h) * 0.06))
    tw, th, l, t = text_size(d, "AI Chat", fnt)
    d.text((cx - tw // 2 - l, cy + s // 2 + int(s * 0.25) - t), "AI Chat", font=fnt, fill=(70, 74, 86))
    return img


ICONS = {
    "Icon.png": 57,
    "Icon@2x.png": 114,
    "Icon-72.png": 72,
    "Icon-72@2x.png": 144,
    "Icon-Small.png": 29,
    "Icon-Small@2x.png": 58,
    "Icon-Small-50.png": 50,
    "Icon-Small-50@2x.png": 100,
}

LAUNCH = {
    "Default.png": (320, 480),
    "Default@2x.png": (640, 960),
    "Default-568h@2x.png": (640, 1136),
    "Default-Portrait~ipad.png": (768, 1004),
    "Default-Portrait@2x~ipad.png": (1536, 2008),
    "Default-Landscape~ipad.png": (1024, 748),
    "Default-Landscape@2x~ipad.png": (2048, 1496),
}

for name, size in ICONS.items():
    make_icon(size).save(os.path.join(OUT, name), "PNG")
    print("icon", name)

for name, (w, h) in LAUNCH.items():
    make_launch(w, h).save(os.path.join(OUT, name), "PNG")
    print("launch", name)
