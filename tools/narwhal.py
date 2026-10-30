"""Animate the narwhal (sprites/narwhal_base.png) into sprites/narwhal.png.

The base is the narwhal as drawn, 61x39, facing left. Frames are made by
moving its pixels, never redrawing them: the body in columns, each lifted or
dropped by a wave that the head barely feels and the fluke feels most, and the
two flippers as wholes. The sheet is frames of 65x45 in a row: 4 idle (a slow
bob, the fluke swaying, the flippers waving) then 6 swimming (a wave running
down the body to the tail, the flippers paddling).

    python3 tools/narwhal.py [preview.gif]
"""
import math
import sys

from PIL import Image

MARGIN = (2, 3)  # room round the base for pixels to move into
BASE = Image.open("sprites/narwhal_base.png").convert("RGBA")
BW, BH = BASE.size
W, H = BW + 2 * MARGIN[0], BH + 2 * MARGIN[1]


def front_flipper(x, y):
    return 15 <= x <= 22 and y >= 28


def back_flipper(x, y):
    return 24 <= x <= 31 and y >= 31


def bend(x):
    # How much of the body's wave reaches column x: hardly any at the head
    # and horn, all of it at the fluke
    return min(max((x - 14) / 44, 0.0), 1.0) ** 1.5


def frame(wave=None, bob=0, tail=0, front=(0, 0), back=(0, 0)):
    """wave is a phase (radians) for the swimming wave, or None to hold the
    body still but for tail (pixels, up) at the fluke. bob lifts it all; front
    and back move the flippers (x, y)"""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    src = BASE.load()
    out = img.load()

    def lift(x):
        if wave is not None:
            return round(2.2 * math.sin(wave - x * 0.16) * bend(x))
        return round(tail * bend(x))

    def put(x, y, c):
        if 0 <= x < W and 0 <= y < H:
            out[x, y] = c

    flippers = []
    for y in range(BH):
        for x in range(BW):
            c = src[x, y]
            if c[3] == 0:
                continue
            if front_flipper(x, y) or back_flipper(x, y):
                flippers.append((x, y, c))
                continue
            put(x + MARGIN[0], y + MARGIN[1] - bob - lift(x), c)
    # Flippers over the body, moving with the body where they join it
    for x, y, c in flippers:
        dx, dy = front if front_flipper(x, y) else back
        root = 18 if front_flipper(x, y) else 27
        put(x + MARGIN[0] + dx, y + MARGIN[1] - bob - lift(root) + dy, c)
    return img


# Flippers only ever move sideways or up into the body, never down off it,
# which would open a gap at the joint
FRAMES = [
    # Idle
    frame(bob=0, tail=0),
    frame(bob=0, tail=1, front=(0, -1), back=(0, 0)),
    frame(bob=1, tail=2, front=(0, -1), back=(0, -1)),
    frame(bob=1, tail=1, front=(0, 0), back=(0, -1)),
] + [
    # Swimming: one full wave in six steps, the flippers paddling back and
    # forth against it
    frame(wave=2 * math.pi * k / 6,
          front=(round(-math.sin(2 * math.pi * k / 6)), -int(math.cos(2 * math.pi * k / 6) > 0.4)),
          back=(round(math.sin(2 * math.pi * k / 6)), -int(math.cos(2 * math.pi * k / 6) < -0.4)))
    for k in range(6)
]

if __name__ == "__main__":
    sheet = Image.new("RGBA", (W * len(FRAMES), H), (0, 0, 0, 0))
    for i, f in enumerate(FRAMES):
        sheet.paste(f, (i * W, 0))
    sheet.save("sprites/narwhal.png")
    if len(sys.argv) > 1:
        def big(f):
            bg = Image.new("RGBA", (W, H), (20, 15, 31, 255))
            bg.alpha_composite(f)
            return bg.resize((W * 6, H * 6), Image.NEAREST).convert("RGB")
        idle = [big(f) for f in FRAMES[:4]] * 2
        swim = [big(f) for f in FRAMES[4:]] * 3
        idle[0].save(sys.argv[1], save_all=True, append_images=idle[1:] + swim,
                     duration=[250] * len(idle) + [100] * len(swim), loop=0)
