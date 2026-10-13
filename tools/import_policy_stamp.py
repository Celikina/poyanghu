"""Import the supplied policy parchment and separate its printed seal for animation."""
import argparse
from pathlib import Path
from PIL import Image, ImageChops

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
args = parser.parse_args()
target = Path(__file__).resolve().parents[1] / "assets/ui/policy-stamp"
target.mkdir(parents=True, exist_ok=True)
blank = Image.open(args.source / "无.png").convert("RGBA")
for name, tier, center in [("基础", "basic", 204), ("有效", "effective", 343), ("深度", "deep", 482)]:
    image = Image.open(args.source / (name + ".png")).convert("RGBA")
    rect = (center - 75, 175, center + 75, 310)
    ink = image.crop(rect)
    baseline = blank.crop(rect)
    diff = ImageChops.difference(ink, baseline)
    mask = diff.convert("RGB").getdata()
    pixels = list(ink.getdata())
    ink.putdata([pixel if max(delta) > 2 else (0, 0, 0, 0) for pixel, delta in zip(pixels, mask)])
    ink.save(target / (tier + "-seal.png"))
    image.paste(baseline, rect[:2])
    image.save(target / (tier + "-page.png"))
blank.save(target / "blank.png")
Image.open(args.source / "章.png").save(target / "seal-original.png")
Image.open(args.source / "纸张.png").save(target / "paper-original.png")
print("Policy stamp: 3 pages + 3 animated seals imported")
