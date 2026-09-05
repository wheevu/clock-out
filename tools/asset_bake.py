#!/usr/bin/env python3
"""Sprite-baking pipeline for the "퇴근" (clock-out) engine.

Converts source PNG pixel-art assets from the Creative/GameDev folder into raw
RGBA blobs the C UI compositor (render/ui.H) loads at runtime.

Outputs (all under assets/baked/, which this script owns):
  - <key>.blob     : exactly w*h*4 raw bytes, row-major RGBA
  - manifest.txt   : one line per sprite: "<key> <w> <h> <key>.blob"
  - CREDITS.txt    : provenance for each source asset

Deterministic and idempotent: re-running produces byte-identical output.
No randomness; fixed crop/frame choices.

Usage:
    python3 tools/asset_bake.py
"""

import os
import sys
from PIL import Image, ImageDraw

# --- locations ---------------------------------------------------------------
# Repo root = parent of the directory holding this script.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
BAKED_DIR = os.path.join(REPO_ROOT, "assets", "baked")

# Source Creative assets. Override with CLOCKOUT_SRC if your layout differs.
SRC_ROOT = os.environ.get(
    "CLOCKOUT_SRC",
    os.path.expanduser("~/Creative/GameDev"),
)

# --- bake plan ---------------------------------------------------------------
# Each entry describes one manifest key and how to derive its blob.
# kind:
#   char  -> crop a single 48x48 frame from a LimeZu 8x20 sheet (row 0, col)
#   icon  -> load + convert to RGBA, NEAREST-downscale so max axis <= size
#   spark -> load + convert to RGBA, crop content bbox, fit within size (NEAREST)
#   card  -> load + convert to RGBA (already small; downscale if needed)
PLAN = [
    {
        "key": "char_player",
        "src": "characters/minji.png",
        "kind": "char",
        "col": 1,
        "pack": "LimeZu Modern Interiors — characters",
        "note": "friendly office worker (standing front-facing frame)",
    },
    {
        "key": "char_boss",
        "src": "characters/yunjin.png",
        "kind": "char",
        "col": 1,
        "pack": "LimeZu Modern Interiors — characters",
        "note": "the boss '주인' (distinct character)",
    },
    {
        "key": "char_kim",
        "src": "characters/kazuha.png",
        "kind": "char",
        "col": 1,
        "pack": "LimeZu Modern Interiors — characters",
        "note": "senior colleague '김대리'",
    },
    {
        "key": "icon_star",
        "src": "ui/kenney_game-icons/PNG/White/1x/star.png",
        "kind": "icon",
        "size": 32,
        "pack": "Kenney CC0 — game-icons",
        "note": "small star icon",
    },
    {
        "key": "fx_spark",
        "src": "vfx/kenney_particle-pack/PNG (Transparent)/spark_01.png",
        "kind": "spark",
        "size": 32,
        "pack": "Kenney CC0 — particle-pack",
        "note": "small spark particle (transparent variant)",
    },
    {
        "key": "card_frame",
        "src": "ui/kenney_playing-cards-pack/PNG/Cards (medium)/card_back.png",
        "kind": "card",
        "pack": "Kenney CC0 — playing-cards-pack",
        "note": "card back used as a frame placeholder",
    },
]

# The local character sheets have four front-facing idle frames in row zero.
# Keep full frame bounds so animation has a stable origin and ground anchor.
for role, source in (("player", "minji"), ("kim", "kazuha"), ("boss", "yunjin")):
    for frame in range(4):
        PLAN.append({
            "key": f"idle_{role}_{frame}",
            "src": f"characters/{source}.png",
            "kind": "char",
            "col": frame,
            "pack": "LimeZu Modern Interiors - characters",
            "note": f"front idle frame {frame}; credit LimeZu",
        })


def load_rgba(rel_path):
    full = os.path.join(SRC_ROOT, rel_path)
    if not os.path.isfile(full):
        sys.exit(f"asset_bake: missing source asset: {full}")
    return Image.open(full).convert("RGBA")


def bake_char(im, col):
    # LimeZu Modern Interiors sheets are 384x960 = 8 cols x 20 rows of 48x48.
    fw, fh = 48, 48
    x0, y0 = col * fw, 0
    crop = im.crop((x0, y0, x0 + fw, y0 + fh))
    return crop.resize((fw, fh), Image.NEAREST)


def fit_within(im, size):
    w, h = im.size
    if w <= size and h <= size:
        return im
    scale = size / max(w, h)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    return im.resize((nw, nh), Image.NEAREST)


def build_blob(spec):
    kind = spec["kind"]
    if kind == "char":
        im = load_rgba(spec["src"])
        out = bake_char(im, spec["col"])
    elif kind == "icon":
        im = load_rgba(spec["src"])
        out = fit_within(im, spec["size"])
    elif kind == "spark":
        im = load_rgba(spec["src"])
        bbox = im.getbbox()
        if bbox is not None:
            im = im.crop(bbox)
        out = fit_within(im, spec["size"])
    elif kind == "card":
        im = load_rgba(spec["src"])
        out = fit_within(im, 64)  # cap any axis at 64
    else:
        sys.exit(f"asset_bake: unknown kind {kind!r}")
    out = out.convert("RGBA")
    return out.tobytes(), out.size


def main():
    os.makedirs(BAKED_DIR, exist_ok=True)

    manifest_lines = []
    for spec in PLAN:
        key = spec["key"]
        blob, (w, h) = build_blob(spec)
        if len(blob) != w * h * 4:
            sys.exit(f"asset_bake: {key} blob size {len(blob)} != {w*h*4}")
        blob_path = os.path.join(BAKED_DIR, f"{key}.blob")
        with open(blob_path, "wb") as f:
            f.write(blob)
        manifest_lines.append(f"{key} {w} {h} {key}.blob")
        print(f"baked {key} {w} x {h}")

    manifest_path = os.path.join(BAKED_DIR, "manifest.txt")
    with open(manifest_path, "w") as f:
        f.write("\n".join(manifest_lines) + "\n")

    write_credits(PLAN)

    print(f"wrote {len(PLAN)} sprites to {BAKED_DIR}")


def write_credits(plan):
    # Deterministic: overwrite (idempotent), credits live at the top of the file.
    lines = []
    lines.append("CREDITS — baked sprite sources (퇴근 / clock-out, local dev only)")
    lines.append("")
    lines.append(
        "These assets are bundled only for local development and README use."
    )
    lines.append(
        "They remain the property of their respective authors under the listed packs."
    )
    lines.append("")
    lines.append("LimeZu credit: https://limezu.itch.io (Modern Interiors)")
    lines.append("Source pack licenses remain in Creative/GameDev/archive/.")
    lines.append("")
    for spec in plan:
        lines.append(
            f"- {spec['key']}: {spec['src']}  "
            f"[{spec['pack']}]  ({spec.get('note','')})"
        )
    lines.append("")
    credits_path = os.path.join(BAKED_DIR, "CREDITS.txt")
    with open(credits_path, "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
