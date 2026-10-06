#!/usr/bin/env python3
"""Composes App Store screenshots from raw simulator captures.

usage: compose_store_screenshots.py RAW_DIR BALLS_DIR OUT_DIR iphone|ipad

RAW_DIR holds captures from UITests/StoreShots.swift and ScreenshotBot.swift; frames are
real gameplay, not mockups. BALLS_DIR comes from `swift AppStore/preview_ball_tiers.swift DIR`.
Headline words wrapped in *asterisks* are drawn in gold.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

TTC = '/System/Library/Fonts/Avenir Next.ttc'
CREAM = (255, 248, 238)
RED = (217, 64, 51)        # the PLAY pill
GOLD = (255, 199, 71)      # streak text

CANVAS = {'iphone': (1320, 2868), 'ipad': (2064, 2752)}

# (kicker, headline, iphone frame, ipad frame, tilt degrees, decoration)
SLIDES = [
    ('Tilt to steer', 'Drop through *every gap*', 'run-005', 'run-006', -7, 'hero'),
    ('Streak bonus', 'Chain drops, *stack points*', 'run-010', 'run-009', 0, None),
    ('Ball tiers', 'Watch your *ball evolve*', 'run-018', 'run-014', 0, 'tiers'),
    ('Game Center', 'Beat your *best*', 'gameover', 'gameover', 0, None),
    ('Two modes', 'Speed run or *Zen*', 'menu-best', 'menu-best', 0, None),
    ('Quick start', 'Learn it in *seconds*', 'tutorial', 'tutorial', 0, None),
]
# Tier index in BallPalette order, with the score that unlocks it.
TIER_ROW = [(0, '0'), (1, '100'), (3, '500'), (5, '1K'), (7, '5K'), (9, '10K')]


def font(size, style):
    for i in range(16):
        f = ImageFont.truetype(TTC, size, index=i)
        if f.getname()[1] == style:
            return f
    raise SystemExit(f'Avenir Next {style} not found')


def background(w, h):
    bg = Image.new('RGB', (w, h))
    d = ImageDraw.Draw(bg)
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)], fill=(int(46 - 26 * t), int(28 - 16 * t), int(18 - 10 * t)))
    # Faint vertical boards, echoing the in-game walnut backdrop.
    boards = Image.new('L', (w, h), 0)
    bd = ImageDraw.Draw(boards)
    bw = w // 6
    for i in range(0, 7, 2):
        bd.rectangle([i * bw, 0, i * bw + bw, h], fill=14)
    for i in range(1, 7):
        bd.line([(i * bw, 0), (i * bw, h)], fill=40, width=max(2, w // 600))
    bg.paste((0, 0, 0), (0, 0), boards)
    # Warm glow behind the device so the game reads as lit from above.
    glow = Image.new('L', (w, h), 0)
    r = int(w * 0.55)
    ImageDraw.Draw(glow).ellipse([w // 2 - r, int(h * 0.58) - r, w // 2 + r, int(h * 0.58) + r], fill=70)
    bg.paste((255, 170, 90), (0, 0), glow.filter(ImageFilter.GaussianBlur(w // 5)))
    return bg


def words(text):
    """[(word, gold)] from a headline where *...* spans are gold."""
    out, gold = [], False
    for raw in text.split():
        start = raw.startswith('*')
        end = raw.endswith('*')
        if start:
            gold = True
        out.append((raw.strip('*'), gold))
        if end:
            gold = False
    return out


def wrap(d, items, f, width):
    """One line if it fits, else the two-line split with the shortest longer line."""
    def length(line):
        return d.textlength(' '.join(w for w, _ in line), font=f)
    if length(items) <= width:
        return [items]
    splits = [(items[:i], items[i:]) for i in range(1, len(items))]
    return list(min(splits, key=lambda p: max(length(p[0]), length(p[1]))))


def draw_line(d, line, f, cx, y):
    total = d.textlength(' '.join(w for w, _ in line), font=f)
    x = cx - total / 2
    space = d.textlength(' ', font=f)
    for w, gold in line:
        d.text((x, y), w, font=f, fill=GOLD if gold else CREAM)
        x += d.textlength(w, font=f) + space


def ball(balls, tier, d):
    return Image.open(balls / f'{tier}.png').convert('RGBA').resize((d, d), Image.LANCZOS)


def paste_with_shadow(bg, img, x, y, blur):
    sh = Image.new('L', bg.size, 0)
    sh.paste(img.getchannel('A').point(lambda a: int(a * 0.6)), (x, y + blur))
    bg.paste((0, 0, 0), (0, 0), sh.filter(ImageFilter.GaussianBlur(blur)))
    bg.paste(img, (x, y), img)


def device(shot, width, kind):
    """Screenshot inside a dark bezel, returned as RGBA."""
    bezel = int(width * (0.028 if kind == 'iphone' else 0.022))
    sw = width - 2 * bezel
    sh = round(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    inner_r = int(sw * (0.12 if kind == 'iphone' else 0.035))
    outer_r = inner_r + bezel
    dev = Image.new('RGBA', (width, sh + 2 * bezel), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dev)
    dd.rounded_rectangle([0, 0, width - 1, sh + 2 * bezel - 1], radius=outer_r, fill=(14, 10, 8, 255))
    # Hairline rim so the bezel separates from the dark background.
    dd.rounded_rectangle([2, 2, width - 3, sh + 2 * bezel - 3], radius=outer_r - 2,
                         outline=(120, 92, 70, 255), width=max(2, width // 400))
    mask = Image.new('L', (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], radius=inner_r, fill=255)
    dev.paste(shot, (bezel, bezel), mask)
    return dev


def compose(src, out, kind, kicker, headline, tilt, deco, balls):
    w, h = CANVAS[kind]
    bg = background(w, h)
    d = ImageDraw.Draw(bg)

    kf = font(int(w * (0.036 if kind == 'iphone' else 0.030)), 'Demi Bold')
    hf = font(int(w * (0.108 if kind == 'iphone' else 0.078)), 'Heavy')
    lines = wrap(d, words(headline), hf, w * 0.86)
    line_h = int(hf.size * 1.12)

    top = int(h * 0.06)
    label = kicker.upper()
    tw = d.textlength(label, font=kf)
    ph, px = int(kf.size * 2.0), int(kf.size * 1.1)
    d.rounded_rectangle([w / 2 - tw / 2 - px, top, w / 2 + tw / 2 + px, top + ph], radius=ph // 2, fill=RED)
    d.text((w / 2, top + ph / 2), label, font=kf, fill=CREAM, anchor='mm')
    y = top + ph + int(h * 0.018)
    for line in lines:
        draw_line(d, line, hf, w / 2, y)
        y += line_h
    text_bottom = y

    shot = Image.open(src).convert('RGB')
    avail_h = h - text_bottom - int(h * 0.03) - int(h * 0.035)
    dev_w = min(int(w * (0.80 if kind == 'iphone' else 0.78)), int(avail_h * shot.width / shot.height))
    dev = device(shot, dev_w, kind)
    if tilt:
        dev = dev.rotate(tilt, resample=Image.BICUBIC, expand=True)
        scale = min(1, avail_h / dev.height, w * 0.92 / dev.width)
        dev = dev.resize((int(dev.width * scale), int(dev.height * scale)), Image.LANCZOS)
    x = (w - dev.width) // 2
    y = text_bottom + int(h * 0.03) + max(0, (avail_h - dev.height) // 2)

    shadow = Image.new('L', (w, h), 0)
    shadow.paste(dev.getchannel('A').point(lambda a: int(a * 0.75)), (x, y + int(h * 0.012)))
    bg.paste((0, 0, 0), (0, 0), shadow.filter(ImageFilter.GaussianBlur(w // 40)))
    bg.paste(dev, (x, y), dev)

    if deco == 'hero':
        # The red ball breaks out of the screen edge, mid-drop.
        dd = int(w * 0.30)
        hero = ball(balls, 0, dd)
        hx = min(x + dev.width - int(dd * 0.62), w - dd - int(w * 0.03))
        paste_with_shadow(bg, hero, hx, y + int(dev.height * 0.50), w // 60)
    elif deco == 'tiers':
        # A row of real ball styles across the lower screen, labelled with unlock scores.
        n = len(TIER_ROW)
        dd = int(w * 0.84 / n * 0.86)
        gap = (w * 0.84 - dd * n) / (n - 1)
        row_y = y + int(dev.height * 0.70)
        lf = font(int(dd * 0.28), 'Heavy')
        plate = Image.new('L', bg.size, 0)
        ImageDraw.Draw(plate).rounded_rectangle(
            [int(w * 0.05), row_y - int(dd * 0.22), int(w * 0.95), row_y + int(dd * 1.62)],
            radius=int(dd * 0.4), fill=190)
        bg.paste((18, 11, 7), (0, 0), plate.filter(ImageFilter.GaussianBlur(4)))
        d = ImageDraw.Draw(bg)
        for i, (tier, label) in enumerate(TIER_ROW):
            bx = int(w * 0.08 + i * (dd + gap))
            paste_with_shadow(bg, ball(balls, tier, dd), bx, row_y, w // 120)
            d.text((bx + dd / 2, row_y + dd + int(dd * 0.12)), label, font=lf, fill=GOLD, anchor='ma')
    bg.save(out, optimize=True)


def main():
    raw, balls, out, kind = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4]
    out.mkdir(parents=True, exist_ok=True)
    for i, (kicker, headline, phone, pad, tilt, deco) in enumerate(SLIDES, 1):
        frame = phone if kind == 'iphone' else pad
        dest = out / f'{i:02d}-{kicker.lower().replace(" ", "-")}.png'
        compose(raw / f'{frame}.png', dest, kind, kicker, headline, tilt, deco, balls)
        print(dest)


if __name__ == '__main__':
    main()
