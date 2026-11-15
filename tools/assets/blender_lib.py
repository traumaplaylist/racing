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
                              export_texcoords=True, export_normals=True,
                              export_vertex_color="ACTIVE", export_all_vertex_colors=True)
    print("exported", path)


# ---------------------------------------------------------------------------- v2 helpers

def smooth_sharp(ob, angle=38):
    """Smooth shading with hard edges above `angle` (Blender >= 4.1)."""
    me = ob.data
    for p in me.polygons:
        p.use_smooth = True
    try:
        me.set_sharp_from_angle(angle=math.radians(angle))
    except Exception:
        pass
    return ob


def apply_modifiers(ob):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target="MESH")
    return ob


def lathe(name, profile, material, seg=32, parent=None, close=False, angle=30):
    """Revolve (radius, x) profile around the X axis."""
    bm = bmesh.new()
    rings = []
    for k in range(seg):
        a = 2 * math.pi * k / seg
        rings.append([bm.verts.new((x, math.cos(a) * r, math.sin(a) * r)) for (r, x) in profile])
    n = len(profile)
    for k in range(seg):
        a, b = rings[k], rings[(k + 1) % seg]
        for i in range(n - 1):
            bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = new_obj(name, bm, material, parent)
    smooth_sharp(ob, angle)
    return ob


def body_loft(name, stations, parent=None, stripe_hw=0.26, subsurf=2, two_tone=True, mats=("Paint", "Stripe", "Dark"), crease=0.0):
    """Subdivision car hull. stations: (y, half_w, z_bottom, z_belt, z_top, top_half_w).
    Ring: 10 points; centre top faces get the Stripe material, the rocker band gets Dark."""
    bm = bmesh.new()
    rings = []
    for (y, w, zb, zbelt, zt, wt) in stations:
        sh = min(stripe_hw, wt * 0.6)
        pts = [(-w * 0.82, zb), (w * 0.82, zb), (w, zb + 0.13), (w, zbelt), (wt, zt), (sh, zt + 0.015),
               (-sh, zt + 0.015), (-wt, zt), (-w, zbelt), (-w, zb + 0.13)]
        rings.append([bm.verts.new((x, y, z)) for (x, z) in pts])
    n = 10
    faces_stripe, faces_dark = [], []
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(n):
            f = bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
            if i == 5:
                faces_stripe.append(f)
            if two_tone and i in (0, 1, 9):
                faces_dark.append(f)
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    if crease > 0:
        # character lines: crease the belt and roof-edge rails, and the end caps
        layer = bm.edges.layers.float.new("crease_edge")
        bm.edges.ensure_lookup_table()
        for a, b in zip(rings[:-1], rings[1:]):
            for i in (2, 3, 4, 7, 8, 9):
                e = bm.edges.get((a[i], b[i]))
                if e:
                    e[layer] = crease
        for ring in (rings[0], rings[-1]):
            for i in range(n):
                e = bm.edges.get((ring[i], ring[(i + 1) % n]))
                if e:
                    e[layer] = crease
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in faces_stripe:
        f.material_index = 1
    for f in faces_dark:
        f.material_index = 2
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(mat(m))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = parent
    if subsurf:
        md = ob.modifiers.new("Sub", "SUBSURF")
        md.levels = subsurf
        md.render_levels = subsurf
    return ob


def cut_wheel_wells(body, wells, r, depth=0.75):
    """Boolean-cut cylinders (axis X) out of the hull at (x, y, z) centres."""
    cutters = []
    for i, (x, y, z) in enumerate(wells):
        c = cyl("cut%d" % i, r, depth, (x, y, z), "Dark", axis="X", seg=28)
        md = body.modifiers.new("Well%d" % i, "BOOLEAN")
        md.operation = "DIFFERENCE"
        md.object = c
        cutters.append(c)
    apply_modifiers(body)
    for c in cutters:
        bpy.data.objects.remove(c)
    smooth_sharp(body, 42)
    return body


def arch_flare(name, centre, r, width, thick, material, parent=None, a0=-15, a1=195, side=1):
    """Fender flare: rectangular profile swept over the wheel (in the YZ plane)."""
    bm = bmesh.new()
    rings = []
    steps = 14
    cx, cy, cz = centre
    for k in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * k / steps)
        ring = []
        for (dr, dx) in ((0, 0), (thick, 0), (thick * 0.7, side * width), (0, side * width)):
            rr = r + dr
            ring.append(bm.verts.new((cx + dx, cy + math.cos(a) * rr, cz + math.sin(a) * rr)))
        rings.append(ring)
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(4):
            bm.faces.new((a[i], a[(i + 1) % 4], b[(i + 1) % 4], b[i]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = new_obj(name, bm, material, parent)
    smooth_sharp(ob, 50)
    return ob


def wheel2(name, r, w, loc, parent=None, lugs=20):
    """Off-road wheel v2: lathed tyre with chunky tread, dished rim with spokes."""
    side = 1 if loc[0] > 0 else -1
    tyre = lathe(name, [(r * 0.6, -w * 0.46), (r * 0.8, -w * 0.5), (r * 0.94, -w * 0.46), (r * 0.985, -w * 0.3),
                        (r * 0.985, w * 0.3), (r * 0.94, w * 0.46), (r * 0.8, w * 0.5), (r * 0.6, w * 0.46)],
                 "Rubber", seg=36, parent=parent)
    tyre.location = loc
    bm = bmesh.new()
    for i in range(lugs):
        a = 2 * math.pi * i / lugs
        for s in (-1, 1):
            lug = bmesh.ops.create_cube(bm, size=1.0)["verts"]
            bmesh.ops.scale(bm, vec=Vector((w * 0.44, 0.105, r * 0.11)), verts=lug)
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(0.42 * s, 3, "Z"), verts=lug)
            bmesh.ops.translate(bm, vec=Vector((s * w * 0.25, 0, r * 0.99)), verts=lug)
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(a + s * math.pi / lugs, 3, "X"), verts=lug)
    new_obj(name + "_tread", bm, "Rubber", tyre)
    # rim: outer dish + inner cover
    lathe(name + "_rim", [(r * 0.62, side * w * 0.47), (r * 0.6, side * w * 0.5), (r * 0.54, side * w * 0.5),
                          (r * 0.5, side * w * 0.3), (r * 0.2, side * w * 0.26), (r * 0.16, side * w * 0.36),
                          (0.0, side * w * 0.36)], "Rim", seg=24, parent=tyre)
    lathe(name + "_back", [(r * 0.62, -side * w * 0.4), (0.0, -side * w * 0.4)], "Dark", seg=16, parent=tyre)
    for k in range(5):
        a = 2 * math.pi * k / 5
        box(name + "_spoke%d" % k, (0.06, r * 0.36, 0.1), (side * w * 0.33, math.cos(a) * r * 0.35, math.sin(a) * r * 0.35),
            "Steel", rot=(a, 0, 0), parent=tyre, bev=0.012)
        cyl(name + "_nut%d" % k, 0.022, 0.04, (side * w * 0.37, math.cos(a + 0.6) * r * 0.1, math.sin(a + 0.6) * r * 0.1),
            "Steel", seg=6, parent=tyre)
    return tyre
