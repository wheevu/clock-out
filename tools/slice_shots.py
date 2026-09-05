#!/usr/bin/env python3
"""Convert checked playable-state captures into the complete README gallery.

Run via make slice-shots so the input frames come from a passing current build.
The contact sheet is for inspection; individual PNGs preserve native pixels.
The GIFs are short state reels, not a claim of continuous free movement.
"""
import argparse
import re
from pathlib import Path
from PIL import Image, ImageDraw

SCREENS = (
    "title", "office", "attendance", "coworker", "combat", "reward",
    "response", "boss", "exit", "defeat", "pause",
)
REELS = {
    "playable-office.gif": ("title", "office", "attendance", "coworker"),
    "playable-combat.gif": ("combat", "reward", "response", "boss"),
    "playable-night.gif": SCREENS,
}
ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, default=Path("/tmp"))
    parser.add_argument("--output-dir", type=Path, default=ROOT / "assets/shots")
    args = parser.parse_args()
    referenced = set(re.findall(r"assets/shots/playable-([a-z]+)\.png",
                               (ROOT / "README.md").read_text()))
    if referenced != set(SCREENS):
        parser.error(f"README gallery mismatch: missing={sorted(set(SCREENS)-referenced)}, "
                     f"unknown={sorted(referenced-set(SCREENS))}")
    referenced_reels = set(re.findall(r"assets/shots/(playable-[a-z]+\.gif)",
                                      (ROOT / "README.md").read_text()))
    if referenced_reels != set(REELS):
        parser.error(f"README reel mismatch: missing={sorted(set(REELS)-referenced_reels)}, "
                     f"unknown={sorted(referenced_reels-set(REELS))}")
    frames = []
    # Validate every capture before replacing any gallery image.
    for name in SCREENS:
        path = args.input_dir / f"clockout-slice-{name}.ppm"
        with Image.open(path) as source:
            if source.size != (640, 360):
                parser.error(f"{path}: expected 640x360, got {source.size}")
            frames.append(source.convert("RGB"))
    args.output_dir.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGB", (1280, 6 * 384), (13, 21, 26))
    draw = ImageDraw.Draw(sheet)
    for i, (name, frame) in enumerate(zip(SCREENS, frames)):
        frame.save(args.output_dir / f"playable-{name}.png")
        x, y = (i % 2) * 640, (i // 2) * 384
        sheet.paste(frame, (x, y + 24))
        draw.text((x + 12, y + 6), name, fill=(199, 171, 108))
    for filename, names in REELS.items():
        reel_frames = [frames[SCREENS.index(name)] for name in names]
        reel_frames[0].save(
            args.output_dir / filename,
            save_all=True,
            append_images=reel_frames[1:],
            duration=850,
            loop=0,
            disposal=2,
            optimize=False,
        )
    # bin/ is ignored; this inspection sheet is not another published asset.
    sheet.save(ROOT / "bin/slice-contact.png")
    print(f"PASS: {len(frames)} playable PNGs and {len(REELS)} GIF reels -> {args.output_dir}")
    print("Contact sheet: bin/slice-contact.png")


if __name__ == "__main__":
    main()
