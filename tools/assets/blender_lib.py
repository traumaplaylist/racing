"""Small modelling helpers for headless Blender (bpy as a Python module, Blender 5.x).

Conventions: Blender Z up, car front = -Y (glTF export turns it into +Z, Godot's forward here).
Materials only carry names (+ a preview colour); Godot replaces them with its own library
by name (scripts/race/mat_lib.gd), so textures stay editable without re-exporting models.
"""
import math
import bpy
import bmesh
from mathutils import Vector, Matrix

PREVIEW = {
    "Paint": (0.9, 0.9, 0.9), "Stripe": (0.95, 0.92, 0.85), "Dark": (0.08, 0.08, 0.08),
    "Steel": (0.5, 0.5, 0.5), "Rubber": (0.03, 0.03, 0.03), "Rim": (0.2, 0.2, 0.22),
    "Glass": (0.05, 0.08, 0.1), "LightFront": (1, 1, 0.9), "LightRear": (1, 0.1, 0.05),
    "Seat": (0.15, 0.12, 0.1), "Glow": (0.2, 1, 1), "Rust": (0.5, 0.25, 0.1),
    "Rock": (0.6, 0.3, 0.2), "Wood": (0.5, 0.35, 0.2), "Sign": (1, 1, 1), "Leaf": (0.4, 0.45, 0.15),
    "Crate": (0.5, 0.35, 0.2), "Barrel": (0.6, 0.2, 0.1), "PickupRepair": (0.2, 1, 0.9),
    "PickupBoost": (1, 0.6, 0.1), "PickupFrame": (0.15, 0.17, 0.2),
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        c = PREVIEW.get(name, (0.8, 0.8, 0.8))
        m.diffuse_color = (*c, 1.0)
    return m


def new_obj(name, bm, material, parent=None, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    me.materials.append(mat(material))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if parent:
        ob.parent = parent
    return ob


def bevel(ob, width=0.03, segments=2, angle=35):
    md = ob.modifiers.new("Bevel", "BEVEL")
    md.width = width
    md.segments = segments
    md.limit_method = "ANGLE"
    md.angle_limit = math.radians(angle)
    md.harden_normals = True
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def box(name, size, loc, material, rot=(0, 0, 0), parent=None, bev=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(rot[0], 3, "X") @ Matrix.Rotation(rot[1], 3, "Y") @ Matrix.Rotation(rot[2], 3, "Z"), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
    ob = new_obj(name, bm, material, parent)
    if bev > 0:
        bevel(ob, bev)
    return ob


def cyl(name, r, depth, loc, material, axis="X", seg=16, parent=None, r2=None, bev=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r,
                          radius2=r if r2 is None else r2, depth=depth)
    if axis == "X":
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), verts=bm.verts)
    elif axis == "Y":
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
    ob = new_obj(name, bm, material, parent, smooth=True)
    if bev > 0:
        bevel(ob, bev, 2, 50)
    return ob


def tube(name, p0, p1, r, material, parent=None, seg=8):
    """Cylinder between two points (roll cages, bull bars)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=d.length)
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix()
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rot, verts=bm.verts)
    bmesh.ops.translate(bm, vec=(p0 + p1) / 2, verts=bm.verts)
    return new_obj(name, bm, material, parent, smooth=True)


def loft(name, stations, material, parent=None, bev=0.04):
    """Car-body loft. stations: list of (y, half_w_bottom, half_w_top, z_bottom, z_top, z_shoulder).
    Each section is a hexagon: bottom corners, shoulders, top corners (tumblehome)."""
    bm = bmesh.new()
    rings = []
    for (y, hwb, hwt, zb, zt, zs) in stations:
        pts = [(-hwb, zb), (hwb, zb), (hwb + 0.04, zs), (hwt, zt), (-hwt, zt), (-hwb - 0.04, zs)]
        rings.append([bm.verts.new((x, y, z)) for (x, z) in pts])
    n = 6
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = new_obj(name, bm, material, parent)
    if bev > 0:
        bevel(ob, bev, 3, 25)
    return ob


def wheel(name, r, w, loc, parent=None, lugs=22):
    """Off-road wheel: tyre with tread lugs + rim + hub. Origin at the axle centre."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=32, radius1=r * 0.93, radius2=r * 0.93, depth=w)
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), verts=bm.verts)
    for i in range(lugs):
        a = 2 * math.pi * i / lugs
        for side in (-1, 1):
            lug = bmesh.ops.create_cube(bm, size=1.0)["verts"]
            bmesh.ops.scale(bm, vec=Vector((w * 0.46, 0.11, r * 0.12)), verts=lug)
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(0.35 * side, 3, "Z"), verts=lug)
            bmesh.ops.translate(bm, vec=Vector((side * w * 0.24, 0, r * 0.95)), verts=lug)
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(a + side * math.pi / lugs, 3, "X"), verts=lug)
    tyre = new_obj(name, bm, "Rubber", parent, smooth=False)
    tyre.location = loc
    side = 1 if loc[0] > 0 else -1
    cyl(name + "_lip", r * 0.62, w * 0.9, (side * 0.02, 0, 0), "Steel", seg=20, parent=tyre)
    cyl(name + "_dish", r * 0.5, w * 0.92, (side * 0.01, 0, 0), "Rim", seg=20, parent=tyre)
    cyl(name + "_hub", r * 0.2, w * 0.98, (side * 0.03, 0, 0), "Steel", seg=10, parent=tyre)
    for k in range(5):
        a = 2 * math.pi * k / 5
        cyl(name + "_nut%d" % k, 0.035, w * 1.0, (side * 0.035, math.cos(a) * r * 0.3, math.sin(a) * r * 0.3), "Steel", seg=6, parent=tyre)
    return tyre


def export_glb(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=False,
                              export_apply=True, export_yup=True, export_materials="EXPORT",
                              export_texcoords=True, export_normals=True)
    print("exported", path)
