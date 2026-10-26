"""CONCEPT ONLY. Turns the Movie Maker frames into a 1280x720 MP4 and a GIF.

Scales each 320x180 frame 4x (nearest), draws the captions and the key or
pad overlay from build/concept/hud_log.json crisply on top, and pipes the
result to ffmpeg.

    python3 tools/concept/compose.py
"""

import json
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "build", "concept")
FRAMES = os.path.join(OUT, "frames")
W, H = 1280, 720
AVENIR = "/System/Library/Fonts/Avenir Next.ttc"


def font(size, face):
    return ImageFont.truetype(AVENIR, size, index={"bold": 2, "regular": 7, "medium": 5}[face])


F_TITLE = font(30, "bold")
F_SUB = font(24, "regular")
F_BIG = font(64, "bold")
F_SMALL = font(30, "regular")
F_KEY = font(22, "bold")
F_KEY_SMALL = font(16, "bold")
F_LABEL = font(17, "medium")

WHITE = (255, 255, 255, 255)
DIM = (255, 255, 255, 150)
PANEL = (0, 0, 0, 205)
SLOW = (120, 205, 255, 255)
PAD = {"A": (115, 215, 90), "B": (230, 90, 75), "X": (90, 155, 240), "Y": (240, 215, 75)}
PAD_KEYS = {"J": "X", "K": "Y", "Space": "A", "Shift": "LT"}


def states():
    with open(os.path.join(OUT, "hud_log.json")) as f:
        log = json.load(f)
    return [(int(frame), state) for frame, state in log]


def state_at(log, i, index):
    while index + 1 < len(log) and log[index + 1][0] <= i:
        index += 1
    return log[index][1], index


def centered(d, y, text, f, fill):
    w = d.textlength(text, font=f)
    d.text(((W - w) / 2, y), text, font=f, fill=fill)


def keycap(d, x, y, w, h, label, down, pulse, f=F_KEY):
    if pulse:
        d.rounded_rectangle((x - 5, y - 5, x + w + 5, y + h + 5), 9, outline=WHITE, width=2)
    if down:
        d.rounded_rectangle((x, y, x + w, y + h), 6, fill=WHITE)
    else:
        d.rounded_rectangle((x, y, x + w, y + h), 6, outline=DIM, width=2)
    tw = d.textlength(label, font=f)
    box = f.getbbox(label)
    th = box[3] - box[1]
    d.text((x + (w - tw) / 2, y + (h - th) / 2 - box[1]), label, font=f, fill=(0, 0, 0, 255) if down else WHITE)


def draw_keyboard(d, s):
    pw, ph = 330, 172
    x0, y0 = W - pw - 20, H - ph - 20
    d.rounded_rectangle((x0, y0, x0 + pw, y0 + ph), 14, fill=PANEL)
    keys, pulse = set(s["keys"]), set(s["pulse"])
    k = 44
    keycap(d, x0 + 64, y0 + 14, k, k, "W", "W" in keys, "W" in pulse)
    keycap(d, x0 + 14, y0 + 64, k, k, "A", "A" in keys, "A" in pulse)
    keycap(d, x0 + 64, y0 + 64, k, k, "S", "S" in keys, "S" in pulse)
    keycap(d, x0 + 114, y0 + 64, k, k, "D", "D" in keys, "D" in pulse)
    keycap(d, x0 + 14, y0 + 118, 88, 38, "shift", "Shift" in keys, False, F_KEY_SMALL)
    keycap(d, x0 + 110, y0 + 118, 98, 38, "space", "Space" in keys, False, F_KEY_SMALL)
    keycap(d, x0 + 222, y0 + 40, k, k, "J", "J" in keys, False)
    keycap(d, x0 + 274, y0 + 40, k, k, "K", "K" in keys, False)
    for x, text in ((x0 + 244, "near"), (x0 + 296, "far")):
        tw = d.textlength(text, font=F_LABEL)
        d.text((x - tw / 2, y0 + 90), text, font=F_LABEL, fill=DIM)


def draw_pad(d, s):
    pw, ph = 330, 172
    x0, y0 = W - pw - 20, H - ph - 20
    d.rounded_rectangle((x0, y0, x0 + pw, y0 + ph), 14, fill=PANEL)
    buttons = {PAD_KEYS[k] for k in s["keys"] if k in PAD_KEYS}
    keycap(d, x0 + 16, y0 + 12, 64, 28, "LT", "LT" in buttons, False, F_KEY_SMALL)
    cx, cy, r = x0 + 70, y0 + 96, 36
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=DIM, width=3)
    sx, sy = s["stick"]
    mag = (sx * sx + sy * sy) ** 0.5
    if mag > 1:
        sx, sy = sx / mag, sy / mag
    dx, dy = cx + sx * 20, cy + sy * 20
    d.ellipse((dx - 17, dy - 17, dx + 17, dy + 17), fill=WHITE if mag > 0 else DIM)
    fx, fy, off, br = x0 + 250, y0 + 82, 36, 18
    for name, (ox, oy) in {"Y": (0, -1), "X": (-1, 0), "B": (1, 0), "A": (0, 1)}.items():
        bx, by = fx + ox * off, fy + oy * off
        col = PAD[name]
        down = name in buttons
        if down:
            d.ellipse((bx - br - 2, by - br - 2, bx + br + 2, by + br + 2), fill=col + (255,))
        else:
            d.ellipse((bx - br, by - br, bx + br, by + br), outline=col + (220,), width=3)
        tw = d.textlength(name, font=F_KEY)
        box = F_KEY.getbbox(name)
        d.text((bx - tw / 2, by - (box[3] - box[1]) / 2 - box[1]), name, font=F_KEY, fill=(0, 0, 0, 255) if down else col + (255,))
    legend = "A jump   X near   Y far   LT build"
    tw = d.textlength(legend, font=F_LABEL)
    d.text((x0 + (pw - tw) / 2, y0 + ph - 28), legend, font=F_LABEL, fill=DIM)


def compose(base, s):
    img = base.resize((W, H), Image.NEAREST).convert("RGBA")
    over = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    if s["card"]:
        centered(d, 280, s["big"], F_BIG, WHITE)
        centered(d, 375, s["small"], F_SMALL, (255, 255, 255, 190))
    else:
        if s["title"]:
            tw = max(d.textlength(s["title"], font=F_TITLE), d.textlength(s["sub"], font=F_SUB))
            d.rounded_rectangle((16, 14, 16 + tw + 36, 14 + 88), 12, fill=PANEL)
            d.text((34, 22), s["title"], font=F_TITLE, fill=WHITE)
            d.text((34, 60), s["sub"], font=F_SUB, fill=(255, 255, 255, 215))
        if s["slow"]:
            for i in range(6):
                d.rectangle((i, i, W - 1 - i, H - 1 - i), outline=SLOW[:3] + (200 - i * 30,))
            text = "SLOW-MO  x0.3"
            tw = d.textlength(text, font=F_TITLE)
            d.rounded_rectangle((W - tw - 60, 14, W - 16, 62), 12, fill=SLOW)
            d.text((W - tw - 38, 20), text, font=F_TITLE, fill=(0, 0, 0, 255))
        if s["show_keys"]:
            (draw_pad if s["pad"] else draw_keyboard)(d, s)
    img.alpha_composite(over)
    return img.convert("RGB")


def main():
    log = states()
    names = sorted(n for n in os.listdir(FRAMES) if n.endswith(".png"))
    mp4 = os.path.join(OUT, "imprint_aiming_concept.mp4")
    enc = subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
         "-framerate", "60", "-i", "-", "-c:v", "libx264", "-preset", "slow", "-crf", "16",
         "-pix_fmt", "yuv420p", "-movflags", "+faststart", mp4],
        stdin=subprocess.PIPE,
    )
    index = 0
    for i, name in enumerate(names):
        s, index = state_at(log, i, index)
        enc.stdin.write(compose(Image.open(os.path.join(FRAMES, name)), s).tobytes())
        if i % 500 == 0:
            print(f"frame {i}/{len(names)}", file=sys.stderr)
    enc.stdin.close()
    enc.wait()
    gif = os.path.join(OUT, "imprint_aiming_concept.gif")
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", mp4, "-vf",
         "fps=20,scale=640:360:flags=lanczos,split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse=dither=none",
         gif],
        check=True,
    )
    print(mp4)
    print(gif)


if __name__ == "__main__":
    main()
