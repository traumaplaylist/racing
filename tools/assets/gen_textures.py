"""Procedural tileable PBR textures for Canyon Clash (original, generated - no third-party assets).

Run:  python tools/assets/gen_textures.py   (needs numpy + Pillow)
Writes PNGs to assets/textures/.
"""
import os
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "textures")
N = 1024
rng = np.random.default_rng(1234)


def noise(n, scale, seed, octaves=5, persistence=0.5):
    """Tileable fractal noise in [0,1] via spectral synthesis of periodic value noise."""
    r = np.random.default_rng(seed)
    out = np.zeros((n, n))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        cells = int(scale * (2 ** o))
        cells = max(1, min(cells, n))
        g = r.random((cells, cells))
        # bicubic-ish periodic upsample using np.roll interpolation
        img = Image.fromarray((g * 255).astype(np.uint8))
        tiled = np.tile(np.array(img), (3, 3))
        big = Image.fromarray(tiled).resize((n * 3, n * 3), Image.BICUBIC)
        a = np.array(big, dtype=np.float64)[n:2 * n, n:2 * n] / 255.0
        out += a * amp
        total += amp
        amp *= persistence
    out /= total
    out = (out - out.min()) / (out.max() - out.min() + 1e-9)
    return out


def ridged(n, scale, seed, octaves=5):
    v = noise(n, scale, seed, octaves)
    return 1.0 - np.abs(v * 2 - 1)


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    nz = np.ones_like(h)
    l = np.sqrt(dx * dx + dy * dy + nz * nz)
    nx, ny, nz = -dx / l, dy / l, nz / l   # OpenGL convention (Godot)
    return np.stack([(nx + 1) / 2, (ny + 1) / 2, (nz + 1) / 2], -1)


def save(name, arr):
    arr = np.clip(arr, 0, 1)
    if arr.ndim == 2:
        img = Image.fromarray((arr * 255).astype(np.uint8), "L")
    else:
        img = Image.fromarray((arr * 255).astype(np.uint8), "RGB")
    img.save(os.path.join(OUT, name), optimize=True)
    print("wrote", name)


def colorize(t, stops):
    """t in [0,1] -> RGB by linear gradient stops [(pos, (r,g,b)), ...]."""
    out = np.zeros(t.shape + (3,))
    pos = [s[0] for s in stops]
    cols = np.array([s[1] for s in stops], dtype=np.float64) / 255.0
    for c in range(3):
        out[..., c] = np.interp(t, pos, cols[:, c])
    return out


def cracks(n, seed, density, width):
    """Thin dark crack network from ridged noise thresholds."""
    r = ridged(n, density, seed, 4)
    return np.clip((r - (1 - width)) / width, 0, 1) ** 2


def asphalt():
    base = noise(N, 6, 1, 6, 0.55)
    grain = noise(N, 128, 2, 2, 0.5)
    patches = noise(N, 2, 3, 3, 0.5)
    cr = cracks(N, 4, 3, 0.035) * (noise(N, 3, 5, 3) > 0.45)
    t = 0.45 * base + 0.35 * grain + 0.2 * patches
    col = colorize(t, [(0, (62, 58, 56)), (0.5, (92, 86, 82)), (1, (128, 120, 112))])
    # sun-faded light patches and dark oil stains
    col *= (1 - 0.35 * cr)[..., None]
    stains = np.clip((noise(N, 4, 6, 4) - 0.7) * 4, 0, 1)
    col *= (1 - 0.25 * stains)[..., None]
    # dust gathering in cracks
    col = col * (1 - cr[..., None] * 0.2) + np.array([0.55, 0.4, 0.3]) * cr[..., None] * 0.15
    save("asphalt_albedo.png", col)
    h = 0.6 * grain + 0.3 * base - 0.8 * cr
    save("asphalt_normal.png", normal_from_height(h, 2.5))
    save("asphalt_rough.png", 0.78 + 0.18 * grain - 0.25 * stains)


def tire_marks():
    """Long streaky dark marks, tiles along V (travel). Alpha in luminance."""
    x = np.linspace(0, 1, N)
    streak = np.zeros((N, N))
    r = np.random.default_rng(9)
    for _ in range(28):
        c = r.uniform(0.1, 0.9)
        w = r.uniform(0.004, 0.012)
        strength = r.uniform(0.2, 0.7)
        streak += strength * np.exp(-((x - c) ** 2) / (2 * w * w))[None, :]
    fade = noise(N, 3, 10, 3)
    a = np.clip(streak * (0.4 + 0.8 * fade), 0, 1)
    rgba = np.zeros((N, N, 4))
    rgba[..., 0:3] = np.array([0.08, 0.07, 0.07])
    rgba[..., 3] = a
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "tiremarks.png"))
    print("wrote tiremarks.png")


def sand():
    big = noise(N, 3, 20, 5)
    ripple_x = np.sin(np.linspace(0, 2 * np.pi * 24, N))[None, :] * 0.5 + 0.5
    warp = noise(N, 4, 21, 3)
    ripples = np.sin((np.linspace(0, 1, N)[None, :] + warp * 0.15) * 2 * np.pi * 24) * 0.5 + 0.5
    grain = noise(N, 200, 22, 2)
    pebbles = np.clip((noise(N, 60, 23, 2) - 0.78) * 6, 0, 1)
    t = 0.5 * big + 0.2 * ripples + 0.3 * grain
    col = colorize(t, [(0, (176, 112, 66)), (0.5, (205, 142, 88)), (1, (226, 172, 116))])
    col = col * (1 - pebbles[..., None] * 0.35) + pebbles[..., None] * np.array([0.42, 0.28, 0.2]) * 0.35
    save("sand_albedo.png", col)
    save("sand_normal.png", normal_from_height(0.4 * ripples + 0.5 * grain + 0.8 * pebbles, 3.0))


def rock():
    """Sandstone with horizontal strata (bands along image V). Used triplanar in world space."""
    y = np.linspace(0, 1, N)[:, None]
    warp = noise(N, 3, 30, 4)
    bands_t = (y + warp * 0.08) * 9
    bands = (np.sin(bands_t * 2 * np.pi) * 0.5 + 0.5)
    layer = np.floor(bands_t) % 3 / 2.0
    detail = noise(N, 24, 31, 4)
    rid = ridged(N, 8, 32, 4)
    t = 0.35 * bands + 0.25 * layer + 0.25 * detail + 0.15 * rid
    col = colorize(t, [(0, (122, 52, 30)), (0.35, (168, 78, 44)), (0.65, (196, 104, 60)), (1, (226, 150, 98))])
    save("rock_albedo.png", col)
    h = 0.5 * rid + 0.3 * detail + 0.4 * (np.abs(np.gradient(layer, axis=0)) > 0.01)
    save("rock_normal.png", normal_from_height(h, 4.0))


def rust_metal():
    base = noise(N, 5, 40, 6)
    rust = np.clip((noise(N, 4, 41, 5) - 0.35) * 2.2, 0, 1)
    pits = noise(N, 90, 42, 2)
    paint = colorize(base, [(0, (110, 112, 108)), (1, (150, 150, 140))])
    rustc = colorize(pits, [(0, (90, 40, 20)), (0.5, (140, 64, 30)), (1, (176, 92, 44))])
    col = paint * (1 - rust[..., None]) + rustc * rust[..., None]
    save("rust_albedo.png", col)
    save("rust_rough.png", 0.55 + 0.4 * rust)
    save("rust_normal.png", normal_from_height(rust * 0.6 + pits * 0.4, 2.0))


def grime():
    """Multiplier for car paint: near-white with dirt and chips. Triplanar on the car."""
    dirt = np.clip((noise(N, 4, 50, 5) - 0.45) * 2.0, 0, 1)
    speck = np.clip((noise(N, 120, 51, 2) - 0.7) * 4, 0, 1)
    chips = np.clip((ridged(N, 10, 52, 3) - 0.985) * 60, 0, 1) * (noise(N, 3, 53, 3) > 0.6)
    col = np.ones((N, N, 3))
    col = col * (1 - dirt[..., None] * 0.35) + dirt[..., None] * np.array([0.55, 0.42, 0.32]) * 0.35
    col = col * (1 - speck[..., None] * 0.25)
    col = col * (1 - chips[..., None]) + chips[..., None] * np.array([0.62, 0.62, 0.6])
    save("grime_albedo.png", col)
    save("grime_rough.png", 0.4 + 0.45 * dirt + 0.2 * chips)


def chevron_sign():
    """Chevron board: light chevrons on rusty dark-red (512x256)."""
    w, h = 1024, 512
    yy, xx = np.mgrid[0:h, 0:w] / np.array([h, w])[:, None, None]
    u = xx * 3.0
    v = np.abs(yy - 0.5) * 2
    phase = (u - v * 0.35) % 1.0
    chev = (phase < 0.42).astype(np.float64)
    border = ((yy < 0.06) | (yy > 0.94) | (xx < 0.02) | (xx > 0.98)).astype(np.float64)
    grime_n = noise(N, 6, 60, 4)[:h, :w]
    base = np.array([0.42, 0.14, 0.08])
    light = np.array([0.98, 0.9, 0.72])
    col = base * (1 - chev[..., None]) + light * chev[..., None]
    col = col * (1 - border[..., None]) + np.array([0.18, 0.16, 0.15]) * border[..., None]
    col *= (0.8 + 0.2 * grime_n)[..., None]
    img = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")
    img.save(os.path.join(OUT, "chevron_sign.png"))
    print("wrote chevron_sign.png")


def wood():
    y = np.linspace(0, 1, N)[:, None]
    warp = noise(N, 4, 70, 4)
    rings = np.sin((y * 40 + warp * 6) * 2 * np.pi) * 0.5 + 0.5
    grain = noise(N, 64, 71, 3)
    t = 0.6 * rings + 0.4 * grain
    col = colorize(t, [(0, (92, 60, 36)), (0.5, (128, 86, 52)), (1, (160, 112, 70))])
    save("wood_albedo.png", col)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    asphalt(); tire_marks(); sand(); rock(); rust_metal(); grime(); chevron_sign(); wood()
