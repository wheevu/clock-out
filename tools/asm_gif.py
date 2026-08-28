#!/usr/bin/env python3
# tools/asm_gif.py -- assemble the demo-reel PPM frames into animated GIFs.
#
# Reads assets/shots/frame_NNN.ppm (P6, 640x360) in numeric order and writes:
#   - one looping GIF per screen group (title, explore, dialogue, choice,
#     messenger, schedule, combat, reward, boss, gameover) into
#     assets/shots/<group>.gif
#   - a combined full reel GIF into assets/shots/reel.gif
#
# Completeness is enforced: every expected frame 1..84 must be present or the
# script exits non-zero (so `make gif` fails if capture failed).
#
# Uses Pillow when available; otherwise falls back to ffmpeg/convert + gifsicle
# via subprocess (paths are passed as argument lists, never via shell string
# concatenation). Paths are handled with pathlib.

import sys
from pathlib import Path
import subprocess

SHOTDIR = Path("assets/shots")
OUT_W, OUT_H = 640, 360
DURATION = 180               # ms per frame

# (group name, first frame, last frame) inclusive, 1-based
GROUPS = [
    ("title",    1,  8),
    ("explore",  9, 16),
    ("dialogue", 17, 24),
    ("choice",   25, 32),
    ("messenger",33, 40),
    ("schedule", 41, 48),
    ("combat",   49, 60),
    ("reward",   61, 68),
    ("boss",     69, 76),
    ("gameover", 77, 84),
]

# The demo reel emits exactly frames 1..84. Only consume those, so stale or
# misnumbered frame_*N.ppm leftovers from earlier runs never contaminate the GIFs.
FIRST_FRAME = 1
LAST_FRAME = 84


def frame_path(n):
    return SHOTDIR / ("frame_%03d.ppm" % n)


def list_frames():
    out = []
    for n in range(FIRST_FRAME, LAST_FRAME + 1):
        p = frame_path(n)
        if p.is_file():
            out.append((n, p))
    return out


def ppm_size(path):
    """Read P6 dimensions without requiring Pillow."""
    with path.open("rb") as f:
        if f.readline().strip() != b"P6":
            raise GifError("not a P6 PPM: %s" % path)
        line = f.readline()
        while line.startswith(b"#"):
            line = f.readline()
        try:
            w, h = (int(value) for value in line.split())
        except (TypeError, ValueError):
            raise GifError("invalid PPM dimensions: %s" % path)
        return w, h


def have_pil():
    try:
        import PIL  # noqa
        return True
    except Exception:
        return False


def load_pil(paths):
    """Load PPMs as native-resolution PIL RGB images."""
    from PIL import Image
    imgs = []
    for p in paths:
        im = Image.open(p)
        if im.mode != "RGB":
            im = im.convert("RGB")
        if im.size != (OUT_W, OUT_H):
            raise GifError("unexpected frame size %s for %s" % (im.size, p))
        imgs.append(im)
    return imgs


def save_gif_pil(path, imgs):
    imgs[0].save(path, save_all=True, append_images=imgs[1:],
                 duration=DURATION, loop=0, optimize=False)
    print("wrote", path, "(%d frames)" % len(imgs))


class GifError(Exception):
    """Raised when the ffmpeg/convert + gifsicle fallback cannot assemble a
    GIF. Propagated to main so `make gif` fails non-zero instead of silently
    emitting a shortened clip."""
    pass


def _convert_one(src, dst):
    """Convert one PPM to a scaled GIF via ffmpeg, falling back to convert.
    Returns True only if a file was actually written. Never raises for a
    missing tool; that is reported as a failed conversion by the caller."""
    try:
        rc = subprocess.run(
            ["ffmpeg", "-y", "-i", str(src),
             "-vf", "scale=%d:%d" % (OUT_W, OUT_H), str(dst)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL).returncode
        if rc == 0 and dst.is_file():
            return True
    except (OSError, FileNotFoundError):
        pass
    try:
        rc = subprocess.run(
            ["convert", str(src),
             "-scale", "%dx%d" % (OUT_W, OUT_H), str(dst)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL).returncode
        if rc == 0 and dst.is_file():
            return True
    except (OSError, FileNotFoundError):
        pass
    return False


def save_gif_gifsicle(path, ppm_paths):
    """Fallback: convert PPMs to GIFs with ffmpeg/convert, then gifsicle.
    All subprocess calls pass argument lists (safe quoting, no shell).

    Returns True on success and raises GifError on any failure: a missing or
    failed frame conversion, a temp-GIF count that does not match the input
    count, or a non-zero gifsicle exit. Every temp frame is removed in
    finally, whether or not conversion succeeded."""
    gifs = []
    try:
        for i, p in enumerate(ppm_paths):
            g = SHOTDIR / ("_tmp_%03d.gif" % i)
            gifs.append(g)  # track for cleanup even if conversion fails
            if not _convert_one(p, g):
                raise GifError(
                    "frame conversion failed for %s (ffmpeg and convert "
                    "both unavailable or failed)" % p)
        # every requested PPM must have produced a temp GIF before assembly
        if len(gifs) != len(ppm_paths):
            raise GifError("expected %d temp GIFs, produced %d"
                           % (len(ppm_paths), len(gifs)))
        missing = [str(g) for g in gifs if not g.is_file()]
        if missing:
            raise GifError("missing temp GIFs before gifsicle: %s"
                           % ", ".join(missing))
        cmd = (["gifsicle", "--loop", "--delay", str(DURATION // 10)]
               + [str(x) for x in gifs] + ["-o", str(path)])
        try:
            rc = subprocess.run(cmd, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL).returncode
        except (OSError, FileNotFoundError):
            rc = 1
        if rc != 0:
            raise GifError("gifsicle failed for %s (rc=%d)" % (path, rc))
        print("wrote", path, "(%d frames, gifsicle)" % len(gifs))
        return True
    finally:
        # remove every temporary gif frame, success or failure
        for g in gifs:
            try:
                g.unlink()
            except OSError:
                pass


def main():
    frames = list_frames()
    if not frames:
        print("error: no frames captured (expected %d..%d); "
              "run `make shots` first" % (FIRST_FRAME, LAST_FRAME),
              file=sys.stderr)
        return 1

    present = {n for (n, _) in frames}
    expected = set(range(FIRST_FRAME, LAST_FRAME + 1))
    missing = sorted(expected - present)
    if missing:
        # compact listing of missing frame numbers
        print("error: %d expected frame(s) missing: %s"
              % (len(missing), ", ".join("%d" % m for m in missing)),
              file=sys.stderr)
        return 1

    try:
        for _n, frame in frames:
            size = ppm_size(frame)
            if size != (OUT_W, OUT_H):
                print("error: unexpected frame size %s for %s; expected %dx%d"
                      % (size, frame, OUT_W, OUT_H), file=sys.stderr)
                return 1
    except (GifError, OSError) as e:
        print("error: %s" % e, file=sys.stderr)
        return 1

    # delete every GIF in the shot dir so that, after assembly, the only
    # GIFs present are exactly the 10 named groups + reel (no stale leftovers).
    for old in SHOTDIR.glob("*.gif"):
        old.unlink()

    use_pil = have_pil()

    def make(path, subset):
        paths = [p for (n, p) in frames if n in subset]
        if not paths:
            return
        if use_pil:
            save_gif_pil(path, load_pil(paths))
        else:
            # raises GifError on any failure; propagated to the caller
            save_gif_gifsicle(path, paths)

    groups = [(name, set(range(a, b + 1))) for (name, a, b) in GROUPS]
    try:
        for name, rng in groups:
            make(SHOTDIR / (name + ".gif"), rng)

        allset = set(n for (n, _) in frames)
        make(SHOTDIR / "reel.gif", allset)
    except GifError as e:
        print("error: %s" % e, file=sys.stderr)
        return 1

    # verify every expected clip exists
    expected_gifs = [SHOTDIR / (name + ".gif") for (name, _a, _b) in GROUPS]
    expected_gifs.append(SHOTDIR / "reel.gif")
    missing_gifs = [str(g) for g in expected_gifs if not g.exists()]
    if missing_gifs:
        print("error: failed to produce: %s"
              % ", ".join(missing_gifs), file=sys.stderr)
        return 1

    print("done: %d named groups + reel" % len(GROUPS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
