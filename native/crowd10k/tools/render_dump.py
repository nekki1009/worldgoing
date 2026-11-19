"""Render crowd10k v2 dump.bin to PNG frames / GIF for visual behaviour checks.

usage: render_dump.py dump.bin out.(gif|png) [every=1] [scale=3] [x0,y0,x1,y1]
colours: blue / black = team 0 / 1 standing (lighter = archers), red = exchanging (FIGHT),
orange = engage / encircle, grey = unconscious, yellow line = arrow in flight,
white box = formation centre (magenta = routed).
"""
import struct, sys
import numpy as np
from PIL import Image, ImageDraw

path, out = sys.argv[1], sys.argv[2]
every = int(sys.argv[3]) if len(sys.argv) > 3 else 1
scale = int(sys.argv[4]) if len(sys.argv) > 4 else 3
crop = [int(v) for v in sys.argv[5].split(",")] if len(sys.argv) > 5 else None

data = open(path, "rb").read()
W, H, N = struct.unpack_from("<3i", data, 0)
off = 12
tf = np.frombuffer(data, np.uint8, W * H, off).reshape(H, W); off += W * H
rr = np.frombuffer(data, np.uint8, W * H, off).reshape(H, W); off += W * H
base = np.zeros((H, W, 3), np.uint8)
walk = (tf & 1) == 1
height = (tf >> 1) & 3
water = (tf & 4) != 0
base[walk & (height == 0)] = (206, 214, 180)
base[walk & (height == 1)] = (176, 170, 140)
base[~walk] = (90, 90, 90)
base[water] = (110, 150, 200)
base[rr == 1] = (230, 200, 120)
bg = Image.fromarray(base).resize((W * scale, H * scale), Image.NEAREST)

S_FIGHT, S_ENGAGE, S_ENCIRCLE = 2, 1, 3
frames, k = [], 0
while off < len(data):
    step, = struct.unpack_from("<i", data, off); off += 4
    xy = np.frombuffer(data, np.float32, 2 * N, off).reshape(N, 2); off += 8 * N
    meta = np.frombuffer(data, np.uint8, N, off); off += N
    nf, = struct.unpack_from("<i", data, off); off += 4
    fc = np.frombuffer(data, np.float32, 3 * nf, off).reshape(nf, 3); off += 12 * nf
    npj, = struct.unpack_from("<i", data, off); off += 4
    pj = np.frombuffer(data, np.float32, 4 * npj, off).reshape(npj, 4); off += 16 * npj
    if k % every:
        k += 1
        continue
    k += 1
    im = bg.copy()
    d = ImageDraw.Draw(im)
    team = meta & 1
    alive = (meta >> 1) & 1
    st = (meta >> 2) & 15
    down = (meta >> 6) & 1
    ranged = (meta >> 7) & 1
    r = max(1.0, scale * 0.35)
    order = np.argsort(xy[:, 1])
    for i in order:
        if not alive[i]:
            continue
        x, y = xy[i] * scale
        if down[i]:
            c = (150, 150, 150)
        elif st[i] == S_FIGHT:
            c = (230, 40, 40)
        elif st[i] in (S_ENGAGE, S_ENCIRCLE):
            c = (250, 150, 0)
        elif team[i] == 0:
            c = (90, 130, 255) if ranged[i] else (30, 60, 200)
        else:
            c = (90, 90, 90) if ranged[i] else (20, 20, 20)
        d.ellipse([x - r, y - r, x + r, y + r], fill=c)
    for p in pj:
        d.line([p[0] * scale, p[1] * scale, p[2] * scale, p[3] * scale], fill=(240, 220, 0), width=1)
    for f in fc:
        x, y = f[0] * scale, f[1] * scale
        d.rectangle([x - 1.5, y - 1.5, x + 1.5, y + 1.5], outline=(255, 0, 255) if int(f[2]) & 2 else (255, 255, 255))
    d.text((4, 4), f"t={step / 30:.1f}s", fill=(0, 0, 0))
    if crop:
        im = im.crop(tuple(v * scale for v in crop))
    frames.append(im)

if out.endswith(".gif"):
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=80, loop=0, optimize=True)
else:
    for j, f in enumerate(frames):
        f.save(out.replace(".png", f"_{j:03d}.png"))
print(len(frames), "frames")
