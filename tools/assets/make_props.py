"""Track props -> assets/models/*.glb : barrier segments, chevron sign, rocks, cliffs,
crate, barrel, bush, pickups.   Run: python tools/assets/make_props.py
"""
import math
import os
import random
import sys
sys.path.insert(0, os.path.dirname(__file__))
import bpy
import bmesh
from mathutils import Vector, noise
from blender_lib import reset, box, cyl, tube, new_obj, export_glb, bevel, mat

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models")


def join_all():
    """Apply modifiers and merge every mesh into one object (one mesh, one surface per
    material) so the game can instance it with MultiMesh."""
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        return
    for o in bpy.context.scene.objects:
        o.select_set(o.type == "MESH")
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.convert(target="MESH")
    if len(meshes) > 1:
        bpy.ops.object.join()
    for o in list(bpy.context.scene.objects):
        if o.type == "EMPTY":
            bpy.data.objects.remove(o)


def out(name):
    join_all()
    export_glb(os.path.join(OUT, name + ".glb"))


def corrugated(name, length, height, z0, waves, depth, material):
    """Corrugated sheet along X (length), facing ±Y, with thickness."""
    bm = bmesh.new()
    nx = waves * 6
    rows = []
    for j in range(2):
        z = z0 + height * j
        row = []
        for i in range(nx + 1):
            x = -length / 2 + length * i / nx
            y = math.sin(i / 6 * 2 * math.pi) * depth
            row.append(bm.verts.new((x, y, z)))
        rows.append(row)
    for i in range(nx):
        bm.faces.new((rows[0][i], rows[0][i + 1], rows[1][i + 1], rows[1][i]))
    ob = new_obj(name, bm, material, smooth=True)
    sol = ob.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.03
    return ob


def barrier(chevron=False):
    """Heavy riveted steel plates on I-beam posts. Road side = -Y."""
    reset()
    random.seed(11 if chevron else 5)
    for i, x in enumerate((-1.0, 1.0)):
        tilt = random.uniform(-0.035, 0.035)
        box("Plate%d" % i, (2.06, 0.05, 1.3), (x, -0.02 * i, 0.72 + random.uniform(-0.03, 0.03)), "Rust", rot=(0, tilt, 0), bev=0.012)
        for sx in (-0.92, -0.3, 0.3, 0.92):
            for z in (0.2, 1.24):
                cyl("Rivet", 0.035, 0.05, (x + sx, -0.05, z), "Steel", axis="Y", seg=6)
        box("Rib%d" % i, (2.0, 0.06, 0.1), (x, -0.045, 0.72), "Steel", bev=0.01)
    for x in (-2.0, 0.0):
        box("PostWeb", (0.05, 0.24, 1.5), (x, 0.13, 0.75), "Steel")
        for y in (0.02, 0.25):
            box("PostFlange", (0.2, 0.03, 1.5), (x, y, 0.75), "Steel")
        box("Brace", (0.06, 0.7, 0.06), (x, 0.45, 0.42), "Steel", rot=(0.75, 0, 0))
        box("Foot", (0.4, 0.5, 0.05), (x, 0.2, 0.025), "Steel")
    tube("TopRail", (-2.0, -0.02, 1.42), (2.0, -0.02, 1.42), 0.045, "Steel")
    if chevron:
        sign_quad("Paint", 3.7, 1.0, (0, -0.062, 0.74), "Sign")
    out("barrier_chevron" if chevron else "barrier")


def sign_quad(name, w, h, loc, material):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    v = [bm.verts.new((-w / 2, 0, -h / 2)), bm.verts.new((w / 2, 0, -h / 2)),
         bm.verts.new((w / 2, 0, h / 2)), bm.verts.new((-w / 2, 0, h / 2))]
    f = bm.faces.new(v)
    for loop, (a, b) in zip(f.loops, ((0, 1), (1, 1), (1, 0), (0, 0))):
        loop[uv].uv = (a, b)
    bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
    return new_obj(name, bm, material)


def chevron_board():
    """Sign on two posts; chevron texture faces -Y (towards drivers when placed)."""
    reset()
    box("Back", (2.6, 0.08, 1.3), (0, 0.05, 1.25), "Steel", bev=0.02)
    sign_quad("Face", 2.5, 1.2, (0, -0.0, 1.25), "Sign")
    for x in (-1.0, 1.0):
        box("Leg", (0.12, 0.12, 1.9), (x, 0.12, 0.95), "Steel")
    out("chevron_board")


SAND_COL = (0.82, 0.60, 0.39, 1.0)


def butte(name, seed, radius, height, layers, elong=1.0, roundness=0.0, top_noise=0.15, seg=56, rows_per_layer=3):
    """Sandstone butte: polar mesh with stepped strata, vertical erosion flutes and a talus
    skirt. Vertex colours: strata shading + sand colour at the base (blends into the ground)."""
    random.seed(seed)
    off = Vector((random.random() * 50, random.random() * 50, random.random() * 50))
    # per-layer inset (terraces): hard caprock layers stick out, soft ones recede
    insets = []
    r = 1.0
    for l in range(layers):
        r = max(0.45, min(1.0, r + random.uniform(-0.16, 0.07)))
        insets.append(r)
    shade = [random.uniform(0.78, 1.08) for _ in range(layers)]
    rows = []
    cols = []
    talus_h = 0.16
    nz = layers * rows_per_layer
    zs = [0.0, talus_h * 0.5, talus_h]
    for k in range(nz + 1):
        zs.append(talus_h + (1 - talus_h) * k / nz)
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    vcol = {}
    for zi, zf in enumerate(zs):
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            d = Vector((math.cos(a), math.sin(a), 0))
            low = noise.fractal(d * 1.3 + off, 0.7, 2.0, 3) * 0.28
            flute = noise.fractal(Vector((math.cos(a) * 5, math.sin(a) * 5, zf * 0.6)) + off, 0.6, 2.2, 3) * 0.09
            if zf < talus_h:
                t = zf / talus_h
                prof = 1.55 - 0.5 * t + noise.noise(d * 3 + off) * 0.08
                c = [1.0, 1.0, 1.0]
                alpha = t * t
                flute *= t
            else:
                lf = (zf - talus_h) / (1 - talus_h) * layers
                l = min(layers - 1, int(lf))
                frac = lf - l
                # slight overhang at the top of a layer, receding foot
                prof = insets[l] * (1.0 - 0.05 * (1 - frac)) * (1 - roundness * ((zf - 0.55) * 1.6) ** 2)
                crev = 0.75 if frac < 0.12 else 1.0
                sh = shade[l] * crev * (0.92 + 0.16 * noise.noise(d * 4 + Vector((0, 0, zf * 9)) + off))
                c = [sh, sh, sh]
                alpha = 1.0
            rad = radius * (1 + low) * (prof + flute)
            v = bm.verts.new((d.x * rad * elong, d.y * rad, zf * height))
            vcol[v] = (min(1.0, c[0] * 0.9), min(1.0, c[1] * 0.9), min(1.0, c[2] * 0.9), alpha)
            ring.append(v)
        rows.append(ring)
    for a_, b_ in zip(rows[:-1], rows[1:]):
        for k in range(seg):
            bm.faces.new((a_[k], a_[(k + 1) % seg], b_[(k + 1) % seg], b_[k]))
    # top cap: fan with a bumpy plateau
    centre = bm.verts.new((0, 0, height * (1 + top_noise * 0.3)))
    vcol[centre] = (0.95, 0.95, 0.95, 1.0)
    inner = []
    for k in range(seg):
        v = rows[-1][k]
        p = v.co * 0.55
        p.z = height * (1 + top_noise * noise.noise(p * 0.2 + off) * 0.5)
        w = bm.verts.new(p)
        vcol[w] = (0.95, 0.95, 0.95, 1.0)
        inner.append(w)
    top = rows[-1]
    for k in range(seg):
        bm.faces.new((top[k], top[(k + 1) % seg], inner[(k + 1) % seg], inner[k]))
        bm.faces.new((inner[k], inner[(k + 1) % seg], centre))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        for loop in f.loops:
            loop[col] = vcol[loop.vert]
    ob = new_obj(name, bm, "Rock")
    from blender_lib import smooth_sharp
    smooth_sharp(ob, 32)
    return ob


def rocks():
    specs = [
        # name, seed, radius, height, layers, elong, roundness
        ("rock_boulder", 1, 1.0, 1.3, 2, 1.0, 0.9),
        ("rock_slab", 2, 1.3, 0.8, 2, 1.4, 0.4),
        ("rock_mesa", 3, 1.0, 1.5, 5, 1.2, 0.0),
        ("rock_spire", 4, 0.55, 2.6, 7, 1.0, 0.15),
        ("cliff", 5, 1.0, 1.7, 6, 2.4, 0.0),
        ("cliff_b", 6, 1.0, 2.0, 7, 1.8, 0.05),
    ]
    for name, seed, rad, h, layers, elong, rnd in specs:
        reset()
        butte(name, seed, rad, h, layers, elong, rnd, seg=40 if layers <= 2 else 56)
        out(name)
    reset()
    for i in range(6):
        random.seed(i)
        o = butte("stone%d" % i, 10 + i, 0.22, 0.2, 1, random.uniform(1.0, 1.5), 1.0, seg=10, rows_per_layer=2)
        o.location = (random.uniform(-1.6, 1.6), random.uniform(-1.6, 1.6), -0.02)
        o.rotation_euler = (0, 0, random.uniform(0, 6.28))
    out("stones")


def crate():
    reset()
    box("Box", (1.2, 1.2, 1.2), (0, 0, 0.6), "Crate", bev=0.02)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("Edge", (0.1, 0.1, 1.24), (sx * 0.57, sy * 0.57, 0.6), "Steel")
    for z in (0.05, 1.15):
        for sy in (-1, 1):
            box("EdgeH", (1.24, 0.1, 0.1), (0, sy * 0.57, z), "Steel")
            box("EdgeH2", (0.1, 1.24, 0.1), (sy * 0.57, 0, z), "Steel")
    out("crate")


def barrel():
    reset()
    cyl("Drum", 0.42, 1.25, (0, 0, 0.625), "Barrel", axis="Z", seg=20)
    for z in (0.25, 0.625, 1.0):
        cyl("Rib", 0.44, 0.05, (0, 0, z), "Steel", axis="Z", seg=20)
    cyl("Lid", 0.38, 0.03, (0, 0, 1.26), "Steel", axis="Z", seg=20)
    out("barrel")


def bush():
    reset()
    random.seed(7)
    bm = bmesh.new()
    for i in range(36):
        h = random.uniform(0.5, 1.1)
        cone = bmesh.ops.create_cone(bm, cap_ends=False, segments=4, radius1=0.08, radius2=0.0, depth=h)["verts"]
        bmesh.ops.translate(bm, vec=Vector((0, 0, h / 2)), verts=cone)
        a = random.uniform(0, 2 * math.pi)
        tilt = random.uniform(0.2, 1.0)
        rot = (Vector((0, 0, 1)).rotation_difference(Vector((math.cos(a) * tilt, math.sin(a) * tilt, 1)).normalized())).to_matrix()
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rot, verts=cone)
        bmesh.ops.translate(bm, vec=Vector((random.uniform(-0.2, 0.2), random.uniform(-0.2, 0.2), 0)), verts=cone)
    new_obj("Bush", bm, "Leaf")
    out("bush")


def pickups():
    reset()
    root = bpy.data.objects.new("Repair", None)
    bpy.context.scene.collection.objects.link(root)
    box("Frame", (1.3, 1.3, 1.3), (0, 0, 0), "PickupFrame", parent=root, bev=0.12)
    for axis in range(3):
        for s in (-1, 1):
            loc = [0, 0, 0]
            loc[axis] = s * 0.66
            a = (0.75, 0.22, 0.04)
            b = (0.22, 0.75, 0.04)
            rot = [(0, math.pi / 2, 0), (math.pi / 2, 0, 0), (0, 0, 0)][axis]
            box("CrossA", a, tuple(loc), "PickupRepair", rot=rot, parent=root)
            box("CrossB", b, tuple(loc), "PickupRepair", rot=rot, parent=root)
    out("pickup_repair")
    reset()
    root = bpy.data.objects.new("Boost", None)
    bpy.context.scene.collection.objects.link(root)
    for row, y in enumerate((0.45, -0.35)):
        for s in (-1, 1):
            box("Chev", (0.95, 0.32, 0.3), (s * 0.33, y + 0.0, 0), "PickupBoost", rot=(0, 0, s * 0.8), parent=root, bev=0.05)
    cyl("Ring", 1.0, 0.08, (0, 0, -0.5), "PickupFrame", axis="Z", seg=24, parent=root)
    out("pickup_boost")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    barrier(); barrier(True); chevron_board(); rocks(); crate(); barrel(); bush(); pickups()
