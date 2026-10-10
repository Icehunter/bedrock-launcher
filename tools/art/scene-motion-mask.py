# Makes Resources/Art/scene-motion.png, the mask that tells the Play page
# shader which parts of scene-hd.jpg move.
# Usage: python3 scene-motion-mask.py scene-hd.jpg scene-motion.png preview.jpg
import sys
import numpy as np
from PIL import Image, ImageFilter, ImageDraw
src, out, preview = sys.argv[1], sys.argv[2], sys.argv[3]
im = Image.open(src).convert("RGB")
W, H = 1280, 720
a = np.asarray(im.resize((W, H), Image.LANCZOS)).astype(np.float32)
r, g, b = a[..., 0], a[..., 1], a[..., 2]
yy, xx = np.mgrid[0:H, 0:W] / np.array([H, W])[:, None, None]
lum = (r + g + b) / 3

# Water: blue/cyan pixels in the valley.
water = (b > r + 18) & (b > 90) & (yy > 0.48) & (xx > 0.36) & (xx < 0.74)
# Waterfalls: bright, low-saturation pixels in the fall areas.
sat = a.max(-1) - a.min(-1)
falls = (lum > 170) & (sat < 70) & (
    ((xx > 0.305) & (xx < 0.345) & (yy > 0.37) & (yy < 0.50)) |
    ((xx > 0.47) & (xx < 0.58) & (yy > 0.62) & (yy < 0.95))
)
water &= ~falls
# Sky and clouds: above the mountain tops, bright or blue.
sky = (yy < 0.30) & ((lum > 150) | (b > r)) & ~((xx < 0.25)) & ~((xx > 0.84))
# Mountain peaks stay still: cut them out of the sky.
peaks = Image.new("L", (W, H), 0)
d = ImageDraw.Draw(peaks)
d.polygon([(300,215),(345,150),(380,110),(405,115),(440,140),(470,110),(505,85),(540,90),(560,120),(600,160),(640,190),(690,230),(690,300),(300,300)], fill=255)
d.polygon([(640,250),(690,190),(705,170),(725,170),(745,200),(775,230),(800,250),(800,300),(640,300)], fill=255)
d.polygon([(820,250),(845,215),(860,210),(880,225),(905,250),(905,300),(820,300)], fill=255)
d.polygon([(960,240),(985,185),(1010,175),(1040,180),(1065,195),(1095,215),(1110,260),(1110,300),(960,300)], fill=255)
d.polygon([(200,215),(230,190),(255,185),(280,205),(300,230),(300,300),(200,300)], fill=255)
sky &= ~(np.asarray(peaks) > 0)
# Mist: pale, low-saturation band between the hills.
mist = (yy > 0.30) & (yy < 0.52) & (lum > 140) & (sat < 90) & ~falls

def soft(m, rad):
    return np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(rad))).astype(np.uint8)

mask = np.stack([soft(water, 1.5), soft(falls, 1.2), soft(sky, 3), soft(mist, 4)], -1)
# One opaque RGB file: sky sits above y=0.30 and mist below, so they share blue.
rgb = np.stack([mask[..., 0], mask[..., 1], np.maximum(mask[..., 2], mask[..., 3])], -1)
Image.fromarray(rgb, "RGB").save(out)

# Preview image: water blue, waterfalls white, sky pink, mist yellow.
p = a.copy() * 0.45
for ch, col in [(0, (40, 120, 255)), (1, (255, 255, 255)), (2, (255, 0, 200)), (3, (255, 220, 0))]:
    m = mask[..., ch:ch + 1] / 255.0
    p = p * (1 - m * 0.8) + np.array(col) * m * 0.8
Image.fromarray(p.clip(0, 255).astype(np.uint8)).save(preview)
print({k: int(v.sum()) for k, v in dict(water=water, falls=falls, sky=sky, mist=mist).items()})
