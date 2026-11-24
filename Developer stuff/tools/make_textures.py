#!/usr/bin/env python3
"""
Draws the InnHopper theme textures as 32-bit TGA files.
Run:  python make_textures.py      (needs Pillow and numpy)
Output goes to <addon folder>/Textures

Texture sizes must be powers of two for the game, so everything here is
256/128/64/32/16 wide or tall.
"""
import os
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "Textures"))
os.makedirs(OUT, exist_ok=True)
SS = 4  # supersampling factor for smooth edges


def save(img, name):
    img = img.convert("RGBA")
    img.save(os.path.join(OUT, name + ".tga"))
    print("wrote %-22s %dx%d" % (name, img.size[0], img.size[1]))


def shrink(img, size):
    return img.resize(size, Image.LANCZOS)


def canvas(w, h):
    return Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))


def vgrad(w, h, top, bottom):
    t = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None]
    arr = np.zeros((h, w, 4), dtype=np.float32)
    for c in range(4):
        arr[:, :, c] = top[c] * (1.0 - t) + bottom[c] * t
    return Image.fromarray(arr.round().astype("uint8"), "RGBA")


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m


def with_alpha(color, a):
    return (color[0], color[1], color[2], a)


# ------------------------------------------------------------------ backgrounds
def background(name, top, bottom, vignette=0.30):
    w = h = 256
    img = vgrad(w, h, top, bottom)
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt(((x - w / 2) / (w / 2)) ** 2 + ((y - h / 2) / (h / 2)) ** 2) / 1.414
    a = 1.0 - vignette * d ** 2
    arr = np.array(img).astype(np.float32)
    arr[:, :, :3] *= a[:, :, None]
    save(Image.fromarray(np.clip(arr, 0, 255).astype("uint8"), "RGBA"), name)


# ------------------------------------------------------------------ buttons (128x32)
def button(name, top, bottom, border, shine=None, radius=3, border_w=2):
    w, h = 128, 32
    W, H = w * SS, h * SS
    img = vgrad(W, H, top, bottom)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, W - 1, H - 1], radius=radius * SS, outline=border, width=border_w * SS)
    if shine:
        y = (border_w + 1) * SS
        d.line([((radius + border_w) * SS, y), (W - (radius + border_w) * SS, y)], fill=shine, width=SS)
    img.putalpha(rounded_mask((W, H), radius * SS))
    save(shrink(img, (w, h)), name)


def button_highlight(name, radius=3, a_top=95, a_bot=25):
    w, h = 128, 32
    W, H = w * SS, h * SS
    img = vgrad(W, H, (255, 255, 255, a_top), (255, 255, 255, a_bot))
    arr = np.array(img).astype(np.float32)
    mask = np.array(rounded_mask((W, H), radius * SS)).astype(np.float32) / 255.0
    arr[:, :, 3] *= mask
    save(shrink(Image.fromarray(arr.astype("uint8"), "RGBA"), (w, h)), name)


def button_set(family, up, down, border, border_down, shine, radius=3, border_w=2, hi=(95, 25)):
    button("btn_%s_up" % family, up[0], up[1], border, shine, radius, border_w)
    button("btn_%s_down" % family, down[0], down[1], border_down, None, radius, border_w)
    button_highlight("btn_%s_hi" % family, radius, hi[0], hi[1])


# ------------------------------------------------------------------ corners (64x64, top-left; mirrored in game)
def corner_bracket(name, gold):
    S = SS
    img = canvas(64, 64)
    d = ImageDraw.Draw(img)
    d.line([(5 * S, 5 * S), (5 * S, 40 * S)], fill=gold, width=2 * S)
    d.line([(5 * S, 5 * S), (40 * S, 5 * S)], fill=gold, width=2 * S)
    faint = with_alpha(gold, 140)
    d.line([(9 * S, 9 * S), (9 * S, 24 * S)], fill=faint, width=S)
    d.line([(9 * S, 9 * S), (24 * S, 9 * S)], fill=faint, width=S)
    d.polygon([(6 * S, 0), (12 * S, 6 * S), (6 * S, 12 * S), (0, 6 * S)], fill=gold)
    save(shrink(img, (64, 64)), name)


def corner_alliance(name, gold, blue):
    S = SS
    img = canvas(64, 64)
    d = ImageDraw.Draw(img)
    d.line([(6 * S, 6 * S), (6 * S, 46 * S)], fill=gold, width=3 * S)
    d.line([(6 * S, 6 * S), (46 * S, 6 * S)], fill=gold, width=3 * S)
    d.arc([12 * S, 12 * S, 38 * S, 38 * S], 180, 270, fill=gold, width=2 * S)
    d.ellipse([0, 0, 15 * S, 15 * S], fill=gold)
    d.ellipse([4 * S, 4 * S, 11 * S, 11 * S], fill=blue)
    for p in ((24, 6), (6, 24), (36, 6), (6, 36)):
        d.ellipse([(p[0] - 2) * S, (p[1] - 2) * S, (p[0] + 2) * S, (p[1] + 2) * S], fill=gold)
    save(shrink(img, (64, 64)), name)


def corner_horde(name, iron, dark, red):
    S = SS
    img = canvas(64, 64)
    d = ImageDraw.Draw(img)
    spike_a = [(2 * S, 2 * S), (54 * S, 7 * S), (2 * S, 14 * S)]
    spike_b = [(2 * S, 2 * S), (7 * S, 54 * S), (14 * S, 2 * S)]
    for poly in (spike_a, spike_b):
        d.polygon(poly, fill=iron)
        d.line(poly + [poly[0]], fill=dark, width=S)
    d.ellipse([1 * S, 1 * S, 19 * S, 19 * S], fill=dark)
    d.ellipse([4 * S, 4 * S, 16 * S, 16 * S], fill=iron)
    d.ellipse([7 * S, 7 * S, 13 * S, 13 * S], fill=red)
    save(shrink(img, (64, 64)), name)


# ------------------------------------------------------------------ headers (256x32)
def header_fade(name, band_top, band_bottom, line):
    w, h = 256, 32
    img = vgrad(w, h, band_top, band_bottom)
    arr = np.array(img).astype(np.float32)
    xn = np.linspace(0, 1, w, dtype=np.float32)
    fade = np.clip((1 - np.abs(2 * xn - 1)) * 3.0, 0.0, 1.0)
    arr[:, :, 3] *= fade[None, :]
    line_alpha = fade * line[3]
    for row in (h - 4, h - 3):
        arr[row, :, 0] = line[0]
        arr[row, :, 1] = line[1]
        arr[row, :, 2] = line[2]
        arr[row, :, 3] = line_alpha
    save(Image.fromarray(np.clip(arr, 0, 255).astype("uint8"), "RGBA"), name)


def header_banner(name, top, bottom, edge, gem, gem_inner):
    S = SS
    w, h = 256, 32
    W, H = w * S, h * S
    pts = [(0, 16), (14, 2), (242, 2), (256, 16), (242, 30), (14, 30)]
    big = [(x * S, y * S) for x, y in pts]
    fill = vgrad(W, H, top, bottom)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).polygon(big, fill=255)
    fill.putalpha(mask)
    d = ImageDraw.Draw(fill)
    d.line(big + [big[0]], fill=edge, width=2 * S)
    cx, cy = 128 * S, 16 * S
    d.polygon([(cx, cy - 10 * S), (cx + 10 * S, cy), (cx, cy + 10 * S), (cx - 10 * S, cy)], fill=gem)
    d.polygon([(cx, cy - 5 * S), (cx + 5 * S, cy), (cx, cy + 5 * S), (cx - 5 * S, cy)], fill=gem_inner)
    save(shrink(fill, (w, h)), name)


def header_jagged(name, top, bottom, edge, spike_fill, eye):
    S = SS
    w, h = 256, 32
    W, H = w * S, h * S
    pts = [(2, 28), (6, 10)]
    x = 6
    up = True
    while x < 250:
        nx = x + 12
        pts.append((nx, 2 if up else 12))
        up = not up
        x = nx
    pts += [(254, 10), (250, 28)]
    big = [(px * S, py * S) for px, py in pts]
    fill = vgrad(W, H, top, bottom)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).polygon(big, fill=255)
    fill.putalpha(mask)
    d = ImageDraw.Draw(fill)
    d.line(big + [big[0]], fill=edge, width=2 * S)
    cx, cy = 128 * S, 17 * S
    d.ellipse([cx - 9 * S, cy - 9 * S, cx + 9 * S, cy + 9 * S], fill=spike_fill, outline=edge, width=S)
    d.ellipse([cx - 4 * S, cy - 4 * S, cx + 4 * S, cy + 4 * S], fill=eye)
    save(shrink(fill, (w, h)), name)


# ------------------------------------------------------------------ arcane family
def background_arcane(name, top, bottom, vignette=0.30):
    import math
    w = h = 256
    base = vgrad(w, h, top, bottom)
    ov = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    cx = cy = w * SS / 2
    col = (150, 130, 255, 36)
    for r in (118, 110, 78):
        d.ellipse([cx - r * SS, cy - r * SS, cx + r * SS, cy + r * SS], outline=col, width=SS)
    for i in range(48):
        a = 2 * math.pi * i / 48
        d.line([(cx + math.cos(a) * 110 * SS, cy + math.sin(a) * 110 * SS),
                (cx + math.cos(a) * 118 * SS, cy + math.sin(a) * 118 * SS)], fill=col, width=SS)
    for rot in (0.0, math.pi / 3):
        pts = []
        for k in range(3):
            ang = rot - math.pi / 2 + k * 2 * math.pi / 3
            pts.append((cx + math.cos(ang) * 78 * SS, cy + math.sin(ang) * 78 * SS))
        d.line(pts + [pts[0]], fill=col, width=SS)
    base.alpha_composite(shrink(ov, (w, h)))
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    dd = np.sqrt(((x - w / 2) / (w / 2)) ** 2 + ((y - h / 2) / (h / 2)) ** 2) / 1.414
    arr = np.array(base).astype(np.float32)
    arr[:, :, :3] *= (1.0 - vignette * dd ** 2)[:, :, None]
    save(Image.fromarray(np.clip(arr, 0, 255).astype("uint8"), "RGBA"), name)


def star_points(cx, cy, long_r, short_r, waist):
    return [(cx, cy - long_r), (cx + waist, cy - waist), (cx + short_r, cy), (cx + waist, cy + waist),
            (cx, cy + long_r), (cx - waist, cy + waist), (cx - short_r, cy), (cx - waist, cy - waist)]


def corner_arcane(name, cyan, violet):
    S = SS
    img = canvas(64, 64)
    d = ImageDraw.Draw(img)
    d.line([(6 * S, 6 * S), (6 * S, 42 * S)], fill=cyan, width=2 * S)
    d.line([(6 * S, 6 * S), (42 * S, 6 * S)], fill=cyan, width=2 * S)
    d.line([(11 * S, 11 * S), (11 * S, 28 * S)], fill=with_alpha(violet, 200), width=S)
    d.line([(11 * S, 11 * S), (28 * S, 11 * S)], fill=with_alpha(violet, 200), width=S)
    pts = star_points(8 * S, 8 * S, 9 * S, 9 * S, 2.6 * S)
    d.polygon(pts, fill=(235, 250, 255, 255))
    d.polygon(star_points(8 * S, 8 * S, 5 * S, 5 * S, 1.6 * S), fill=cyan)
    for p in ((22, 6), (6, 22), (34, 6), (6, 34)):
        d.ellipse([(p[0] - 1.5) * S, (p[1] - 1.5) * S, (p[0] + 1.5) * S, (p[1] + 1.5) * S], fill=violet)
    save(shrink(img, (64, 64)), name)


def header_arcane(name, band_top, band_bottom, line, cyan):
    w, h = 256, 32
    img = vgrad(w, h, band_top, band_bottom)
    arr = np.array(img).astype(np.float32)
    xn = np.linspace(0, 1, w, dtype=np.float32)
    fade = np.clip((1 - np.abs(2 * xn - 1)) * 3.0, 0.0, 1.0)
    arr[:, :, 3] *= fade[None, :]
    for row in (h - 4, h - 3):
        arr[row, :, 0], arr[row, :, 1], arr[row, :, 2] = line[0], line[1], line[2]
        arr[row, :, 3] = fade * line[3]
    base = Image.fromarray(np.clip(arr, 0, 255).astype("uint8"), "RGBA")
    S = SS
    ov = canvas(w, h)
    d = ImageDraw.Draw(ov)
    d.polygon(star_points(128 * S, 15 * S, 13 * S, 13 * S, 3.2 * S), fill=(235, 250, 255, 255))
    d.polygon(star_points(128 * S, 15 * S, 7 * S, 7 * S, 2.0 * S), fill=cyan)
    base.alpha_composite(shrink(ov, (w, h)))
    save(base, name)


# ------------------------------------------------------------------ shared icons
def gear(name):
    import math
    S = 4
    n = 128
    k = 2 * 0.88            # 128px canvas, gear drawn at 88% so its teeth never touch the texture edge
    img = Image.new("RGBA", (n * S, n * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = cy = n * S / 2
    teeth = 8
    for i in range(teeth):
        a = 2 * math.pi * i / teeth
        ca, sa = math.cos(a), math.sin(a)
        r0, r1, half = 20 * S * k, 29 * S * k, 5.5 * S * k
        px, py = -sa, ca
        pts = [
            (cx + ca * r0 + px * half, cy + sa * r0 + py * half),
            (cx + ca * r1 + px * half * 0.8, cy + sa * r1 + py * half * 0.8),
            (cx + ca * r1 - px * half * 0.8, cy + sa * r1 - py * half * 0.8),
            (cx + ca * r0 - px * half, cy + sa * r0 - py * half),
        ]
        d.polygon(pts, fill=(255, 255, 255, 255))
    d.ellipse([cx - 22 * S * k, cy - 22 * S * k, cx + 22 * S * k, cy + 22 * S * k], fill=(255, 255, 255, 255))
    d.ellipse([cx - 9 * S * k, cy - 9 * S * k, cx + 9 * S * k, cy + 9 * S * k], fill=(0, 0, 0, 0))
    save(shrink(img, (n, n)), name)


def close_x(name):
    S = 8
    n = 64
    img = Image.new("RGBA", (n * S, n * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w = 9 * S
    d.line([(16 * S, 16 * S), (48 * S, 48 * S)], fill=(255, 255, 255, 255), width=w)
    d.line([(48 * S, 16 * S), (16 * S, 48 * S)], fill=(255, 255, 255, 255), width=w)
    for p in ((16, 16), (48, 48), (48, 16), (16, 48)):
        r = w / 2
        d.ellipse([p[0] * S - r, p[1] * S - r, p[0] * S + r, p[1] * S + r], fill=(255, 255, 255, 255))
    save(shrink(img, (n, n)), name)


def check_box(name):
    S = SS * 2
    n = 32
    img = Image.new("RGBA", (n * S, n * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([2 * S, 2 * S, 30 * S - 1, 30 * S - 1], radius=4 * S,
                        fill=(255, 255, 255, 38), outline=(255, 255, 255, 255), width=2 * S)
    save(shrink(img, (n, n)), name)


def check_mark(name):
    S = SS * 2
    n = 32
    img = Image.new("RGBA", (n * S, n * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pts = [(8 * S, 17 * S), (14 * S, 23 * S), (25 * S, 9 * S)]
    d.line(pts, fill=(255, 255, 255, 255), width=4 * S)
    for p in pts:
        r = 2 * S
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=(255, 255, 255, 255))
    save(shrink(img, (n, n)), name)


def knob(name):
    S = SS * 2
    w, h = 16, 32
    img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([1 * S, 1 * S, 15 * S - 1, 31 * S - 1], radius=5 * S,
                        fill=(225, 225, 225, 255), outline=(255, 255, 255, 255), width=S)
    d.line([(8 * S, 10 * S), (8 * S, 22 * S)], fill=(150, 150, 150, 255), width=S)
    save(shrink(img, (w, h)), name)


# ------------------------------------------------------------------ small square header buttons (32x32)
def _chamfer_poly(size, inset, cut):
    lo, hi = inset, size - 1 - inset
    return [(lo + cut, lo), (hi - cut, lo), (hi, lo + cut), (hi, hi - cut),
            (hi - cut, hi), (lo + cut, hi), (lo, hi - cut), (lo, lo + cut)]


def square_button(name, top, bottom, rim, outline, shine=None):
    """Red square with chamfered corners, matching the game's own close button (rim, body, black outline)."""
    w = h = 32
    W = H = w * SS
    body = vgrad(W, H, top, bottom)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.polygon(_chamfer_poly(W, 0, 6 * SS), fill=outline)                    # black outline
    d.polygon(_chamfer_poly(W, 2 * SS, 5 * SS), fill=rim)                   # bright red rim
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).polygon(_chamfer_poly(W, 5 * SS, 3 * SS), fill=255)
    img.paste(body, (0, 0), mask)                                           # darker red body
    if shine:
        d.line([(9 * SS, 6 * SS), (W - 9 * SS, 6 * SS)], fill=shine, width=SS)
    save(shrink(img, (w, h)), name)


def square_highlight(name):
    w = h = 32
    W = H = w * SS
    img = vgrad(W, H, (255, 255, 255, 90), (255, 255, 255, 25))
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).polygon(_chamfer_poly(W, 2 * SS, 5 * SS), fill=255)
    arr = np.array(img).astype(np.float32)
    arr[:, :, 3] *= np.array(mask).astype(np.float32) / 255.0
    save(shrink(Image.fromarray(arr.astype("uint8"), "RGBA"), (w, h)), name)


# ================================================================== build everything
GOLD_POL = (200, 168, 90, 255)

# --- Alliance: slate navy, steel gold
background("bg_alliance", (34, 44, 64, 247), (13, 17, 27, 247))
corner_bracket("corner_alliance", GOLD_POL)
header_fade("header_alliance", (60, 76, 108, 215), (22, 28, 44, 235), (200, 168, 90, 255))
button_set("alliance",
           ((54, 66, 92, 255), (28, 36, 54, 255)), ((18, 24, 36, 255), (40, 50, 72, 255)),
           (200, 168, 90, 255), (140, 118, 64, 255), (255, 240, 200, 120))

# --- Horde: dark crimson, steel gold
background("bg_horde", (66, 30, 32, 247), (27, 12, 13, 247))
corner_bracket("corner_horde", GOLD_POL)
header_fade("header_horde", (112, 52, 56, 215), (44, 20, 22, 235), (200, 168, 90, 255))
button_set("horde",
           ((98, 48, 52, 255), (54, 24, 26, 255)), ((36, 16, 18, 255), (72, 34, 38, 255)),
           (200, 168, 90, 255), (140, 118, 64, 255), (255, 240, 200, 120))

# --- Dark: flat charcoal buttons
button_set("dark",
           ((44, 44, 49, 255), (37, 37, 42, 255)), ((29, 29, 33, 255), (35, 35, 40, 255)),
           (76, 76, 84, 255), (62, 62, 70, 255), None, radius=2, border_w=2, hi=(30, 12))

# --- cogwheel button
square_button("sq_up", (96, 0, 0, 255), (64, 0, 0, 255), (150, 8, 0, 255), (6, 2, 2, 255), (255, 120, 90, 60))
square_button("sq_down", (58, 0, 0, 255), (84, 0, 0, 255), (104, 4, 0, 255), (6, 2, 2, 255))
square_highlight("sq_hi")

# --- shared icons, tinted per theme
gear("gear")
close_x("close_x")
check_box("check_box")
check_mark("check_mark")
knob("knob")


def patch_dot(name):
    """Soft round white dot; tinted dark red in game to cover the X painted into the game's close button."""
    w = h = 32
    W = H = w * SS
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([3 * SS, 3 * SS, W - 3 * SS, H - 3 * SS], fill=(255, 255, 255, 255))
    from PIL import ImageFilter
    img = img.filter(ImageFilter.GaussianBlur(1.6 * SS))
    save(shrink(img, (w, h)), name)


patch_dot("patch_dot")


def outlined_icon(src, name, fill, outline, grow=2):
    """Same shape as a white icon, filled with a colour and a dark outline (used on the vanilla squares)."""
    from PIL import ImageFilter
    im = Image.open(os.path.join(OUT, src + ".tga")).convert("RGBA")
    a = im.split()[3]
    big = a.resize((a.width * 2, a.height * 2), Image.LANCZOS)
    ring = big.filter(ImageFilter.MaxFilter(2 * grow + 1))
    out = Image.new("RGBA", big.size, (0, 0, 0, 0))
    out.paste(Image.new("RGBA", big.size, outline), (0, 0), ring)
    out.paste(Image.new("RGBA", big.size, fill), (0, 0), big)
    save(shrink(out, im.size), name)


outlined_icon("close_x", "close_x_gold", (255, 223, 36, 255), (70, 40, 0, 255))
outlined_icon("gear", "gear_gold", (255, 223, 36, 255), (70, 40, 0, 255), grow=3)
print("done")
