#!/usr/bin/env python3
# tools/asm_gif.py -- assemble the demo-reel PPM frames into animated GIFs.
#
# Reads assets/shots/frame_NNN.ppm (P6, 320x240) in numeric order, upscales
# each x2 (640x480) with nearest-neighbor, and writes:
#   - one looping GIF per screen group (title, dialogue, choice, combat, boss,
#     gameover) into assets/shots/<group>.gif
#   - a combined full reel GIF into assets/shots/reel.gif
#
# If Pillow is missing it falls back to gifsicle + ffmpeg/convert.
# If no frames exist yet it prints "no frames yet" and exits 0.

import glob
import os
import re
import sys

SHOTDIR = "assets/shots"
OUT_W, OUT_H = 640, 480      # 320x240 upscaled x2
DURATION = 120               # ms per frame

# (group name, first frame, last frame) inclusive, 1-based
GROUPS = [
    ("title",    1,  6),
    ("dialogue", 7, 14),
    ("choice",  15, 22),
    ("combat",  23, 32),
    ("boss",    33, 36),
    ("gameover",37, 40),
]


def frame_path(n):
    return os.path.join(SHOTDIR, "frame_%03d.ppm" % n)


def list_frames():
    pat = os.path.join(SHOTDIR, "frame_*.ppm")
    out = []
    for p in glob.glob(pat):
        m = re.search(r"frame_(\d+)\.ppm$", p)
        if m:
            out.append((int(m.group(1)), p))
    out.sort(key=lambda t: t[0])
    return out


def load_pil(paths):
    """Load PPMs as scaled PIL RGB images."""
    from PIL import Image
    imgs = []
    for p in paths:
        im = Image.open(p)
        if im.mode != "RGB":
            im = im.convert("RGB")
        im = im.resize((OUT_W, OUT_H), Image.NEAREST)
        imgs.append(im)
    return imgs


def save_gif_pil(path, imgs):
    imgs[0].save(path, save_all=True, append_images=imgs[1:],
                 duration=DURATION, loop=0, optimize=False)
    print("wrote", path, "(%d frames)" % len(imgs))


def save_gif_gifsicle(path, ppm_paths):
    """Fallback: convert PPMs to GIFs with ffmpeg/convert, then gifsicle."""
    gifs = []
    for i, p in enumerate(ppm_paths):
        g = os.path.join(SHOTDIR, "_tmp_%03d.gif" % i)
        ok = (os.system("ffmpeg -y -i %s -vf scale=%d:%d %s >/dev/null 2>&1"
                        % (p, OUT_W, OUT_H, g)) == 0)
        if not ok:
            ok = (os.system("convert %s -scale %dx%d %s >/dev/null 2>&1"
                            % (p, OUT_W, OUT_H, g)) == 0)
        if ok:
            gifs.append(g)
    if not gifs:
        print("fallback failed: no gif frames produced", file=sys.stderr)
        return
    cmd = ["/opt/homebrew/bin/gifsicle", "--loop",
           "--delay", str(DURATION // 10)] + gifs + ["-o", path]
    if os.system(" ".join(cmd)) == 0:
        print("wrote", path, "(%d frames, gifsicle)" % len(gifs))
    for g in gifs:
        try:
            os.remove(g)
        except OSError:
            pass


def main():
    frames = list_frames()
    if not frames:
        print("no frames yet")
        return 0

    have_pil = True
    try:
        import PIL  # noqa
    except Exception:
        have_pil = False

    def make(path, subset):
        paths = [p for (n, p) in frames if n in subset]
        if not paths:
            return
        if have_pil:
            save_gif_pil(path, load_pil(paths))
        else:
            save_gif_gifsicle(path, paths)

    # group ranges -> sets
    groups = [(name, set(range(a, b + 1))) for (name, a, b) in GROUPS]
    for name, rng in groups:
        make(os.path.join(SHOTDIR, name + ".gif"), rng)

    # combined full reel
    allset = set(n for (n, _) in frames)
    make(os.path.join(SHOTDIR, "reel.gif"), allset)
    return 0


if __name__ == "__main__":
    sys.exit(main())
