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


def barrier():
    reset()
    corrugated("Panel", 4.0, 0.95, 0.15, 7, 0.04, "Rust")
    corrugated("PanelTop", 4.0, 0.12, 1.1, 7, 0.02, "Rust")
    for x in (-1.95, 1.95):
        box("Post", (0.14, 0.2, 1.35), (x, -0.08, 0.66), "Steel", bev=0.01)
        box("Foot", (0.35, 0.45, 0.06), (x, -0.1, 0.03), "Steel")
    box("Rail", (4.0, 0.08, 0.1), (0, -0.12, 0.95), "Steel")
    out("barrier")


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


def displaced(name, seed, size, scale, strength, flatten_top=None, subdiv=4):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    random.seed(seed)
    off = Vector((random.random() * 100, random.random() * 100, random.random() * 100))
    for v in bm.verts:
        p = v.co.copy()
        n = noise.fractal(p * scale + off, 0.6, 2.0, 4)
        strata = math.sin((p.z * 6 + noise.noise(p * 2 + off) * 0.8) * math.pi) * 0.04
        v.co = p * (1 + n * strength + strata)
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        if flatten_top is not None and v.co.z > flatten_top:
            v.co.z = flatten_top + (v.co.z - flatten_top) * 0.08
    # sit on the ground
    minz = min(v.co.z for v in bm.verts)
    for v in bm.verts:
        v.co.z -= minz + 0.4
    ob = new_obj(name, bm, "Rock")
    for p in ob.data.polygons:
        p.use_smooth = False
    dec = ob.modifiers.new("Dec", "DECIMATE")
    dec.ratio = 0.5
    return ob


def rocks():
    specs = [
        ("rock_boulder", 1, (1.0, 0.9, 0.75), 1.4, 0.35, None),
        ("rock_slab", 2, (1.3, 1.0, 0.45), 1.2, 0.3, 0.3),
        ("rock_mesa", 3, (1.0, 0.95, 1.4), 1.0, 0.25, 1.05),
        ("rock_spire", 4, (0.6, 0.6, 1.9), 1.6, 0.3, 1.7),
        ("cliff", 5, (2.6, 0.9, 1.3), 0.9, 0.28, 1.0),
    ]
    for name, seed, size, sc, st, flat in specs:
        reset()
        displaced(name, seed, size, sc, st, flat)
        out(name)
    reset()
    for i in range(5):
        random.seed(i)
        o = displaced("stone%d" % i, 10 + i, (0.25, 0.2, 0.16), 2.0, 0.35, None, 2)
        o.location = (random.uniform(-1.5, 1.5), random.uniform(-1.5, 1.5), 0.0)
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
    barrier(); chevron_board(); rocks(); crate(); barrel(); bush(); pickups()
