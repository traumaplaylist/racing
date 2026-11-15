"""Builds Buggy and Bruiser car models -> assets/models/car_<type>.glb

Run:  python tools/assets/make_cars.py      (needs `pip install bpy`, Blender 5.x)
Node names the game relies on: Body, Wheel_FL/FR/RL/RR, Weapon_blaster, Weapon_pulse, Muzzle.
"""
import os
import sys
sys.path.insert(0, os.path.dirname(__file__))
import bpy
from blender_lib import reset, box, cyl, tube, loft, wheel, export_glb, bevel

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models")


def empty(name, parent=None, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.parent = parent
    e.location = loc
    return e


def weapons(body, z):
    """Roof-mounted weapons; the game shows the one equipped. Barrel points to -Y (front)."""
    bl = empty("Weapon_blaster", body, (0, -0.15, z))
    box("bl_base", (0.5, 0.6, 0.18), (0, 0, 0.09), "Dark", parent=bl, bev=0.03)
    box("bl_house", (0.42, 0.7, 0.26), (0, -0.05, 0.3), "Steel", parent=bl, bev=0.04)
    for x in (-0.1, 0.1):
        cyl("bl_barrel%d" % (x > 0), 0.05, 0.75, (x, -0.7, 0.32), "Dark", axis="Y", seg=10, parent=bl)
        cyl("bl_tip%d" % (x > 0), 0.065, 0.08, (x, -1.06, 0.32), "Glow", axis="Y", seg=10, parent=bl)
    pu = empty("Weapon_pulse", body, (0, -0.1, z))
    box("pu_base", (0.6, 0.7, 0.18), (0, 0, 0.09), "Dark", parent=pu, bev=0.03)
    cyl("pu_drum", 0.3, 0.75, (0, -0.05, 0.42), "Steel", axis="Y", seg=16, parent=pu, bev=0.02)
    cyl("pu_barrel", 0.13, 0.7, (0, -0.75, 0.42), "Dark", axis="Y", seg=14, parent=pu)
    for k, y in enumerate((-0.45, -0.75, -1.02)):
        cyl("pu_ring%d" % k, 0.17, 0.06, (0, y, 0.42), "Glow", axis="Y", seg=14, parent=pu)
    empty("Muzzle", body, (0, -1.25, z + 0.35))


def buggy():
    reset()
    root = empty("Car")
    body = loft("Body", [
        (-2.0, 0.70, 0.55, 0.42, 0.70, 0.60),
        (-1.65, 0.86, 0.70, 0.36, 0.84, 0.68),
        (-0.70, 0.92, 0.80, 0.34, 0.92, 0.74),
        (0.90, 0.92, 0.82, 0.34, 0.96, 0.76),
        (1.75, 0.88, 0.74, 0.40, 0.94, 0.74),
        (1.95, 0.80, 0.62, 0.46, 0.86, 0.70),
    ], "Paint", parent=root)
    # wide stripe along the centre line, over hood and deck
    box("StripeHood", (0.5, 1.3, 0.02), (0, -1.3, 0.88), "Stripe", rot=(-0.12, 0, 0), parent=root)
    box("StripeDeck", (0.5, 1.0, 0.02), (0, 1.35, 0.965), "Stripe", parent=root)
    # flared wheel arches (dark plastic) → wide, aggressive stance
    for x in (-1, 1):
        for y in (-1.25, 1.25):
            box("Arch", (0.34, 1.25, 0.16), (x * 0.98, y, 0.95), "Dark", rot=(0, x * 0.25, 0), parent=root, bev=0.04)
        box("Sill", (0.14, 1.2, 0.18), (x * 0.96, 0, 0.42), "Dark", parent=root, bev=0.03)
    # open cockpit: seats, dash, roll cage (Buggy silhouette = open frame)
    box("Tub", (1.5, 1.5, 0.2), (0, 0.15, 0.86), "Dark", parent=root)
    for x in (-0.38, 0.38):
        box("Seat", (0.5, 0.55, 0.22), (x, 0.3, 1.02), "Seat", parent=root, bev=0.05)
        box("SeatBack", (0.5, 0.14, 0.62), (x, 0.62, 1.25), "Seat", rot=(0.18, 0, 0), parent=root, bev=0.05)
    box("Dash", (1.5, 0.3, 0.2), (0, -0.62, 1.02), "Dark", parent=root, bev=0.03)
    box("Windshield", (1.4, 0.05, 0.36), (0, -0.72, 1.24), "Glass", rot=(0.45, 0, 0), parent=root)
    r = 0.045
    for x in (-0.72, 0.72):
        tube("CageA", (x, -0.7, 0.95), (x * 0.92, -0.25, 1.68), r, "Steel", root)
        tube("CageB", (x * 0.92, -0.25, 1.68), (x * 0.92, 0.85, 1.68), r, "Steel", root)
        tube("CageC", (x * 0.92, 0.85, 1.68), (x, 1.15, 0.96), r, "Steel", root)
    tube("CageTop1", (-0.66, -0.25, 1.68), (0.66, -0.25, 1.68), r, "Steel", root)
    tube("CageTop2", (-0.66, 0.85, 1.68), (0.66, 0.85, 1.68), r, "Steel", root)
    tube("CageX", (-0.66, 0.85, 1.68), (0.66, 1.1, 0.98), r, "Steel", root)
    box("RoofPanel", (1.35, 1.1, 0.05), (0, 0.3, 1.71), "Paint", parent=root, bev=0.015)
    box("RoofStripe", (0.5, 1.12, 0.06), (0, 0.3, 1.72), "Stripe", parent=root)
    # rear deck vents + engine
    for i in range(5):
        box("Vent", (0.9, 0.06, 0.05), (0, 1.15 + i * 0.13, 0.99), "Dark", parent=root)
    # bull bar + skid plate
    tube("BullH", (-0.75, -2.15, 0.72), (0.75, -2.15, 0.72), 0.05, "Steel", root)
    tube("BullL", (-0.75, -2.15, 0.45), (0.75, -2.15, 0.45), 0.05, "Steel", root)
    for x in (-0.55, 0.55):
        tube("BullV", (x, -2.15, 0.4), (x, -2.15, 0.78), 0.045, "Steel", root)
        tube("BullS", (x, -2.15, 0.6), (x, -1.85, 0.6), 0.04, "Steel", root)
    box("Skid", (1.4, 0.5, 0.06), (0, -1.95, 0.36), "Steel", rot=(0.3, 0, 0), parent=root)
    # lights
    for x in (-0.52, 0.52):
        box("HeadL", (0.34, 0.06, 0.12), (x, -2.0, 0.66), "LightFront", parent=root)
        box("TailL", (0.38, 0.05, 0.1), (x, 1.97, 0.78), "LightRear", parent=root)
    # rear wing
    box("Wing", (1.7, 0.42, 0.05), (0, 1.85, 1.32), "Paint", rot=(0.12, 0, 0), parent=root, bev=0.015)
    for x in (-0.6, 0.6):
        box("WingPost", (0.05, 0.22, 0.4), (x, 1.85, 1.1), "Dark", parent=root)
        box("WingEnd", (0.04, 0.5, 0.25), (x * 1.42, 1.85, 1.35), "Dark", parent=root)
    tube("Exhaust", (0.45, 1.9, 0.48), (0.45, 2.1, 0.48), 0.06, "Steel", root)
    weapons(root, 1.74)
    for name, x, y in (("Wheel_FL", -1.08, -1.25), ("Wheel_FR", 1.08, -1.25), ("Wheel_RL", -1.08, 1.3), ("Wheel_RR", 1.08, 1.3)):
        w = wheel(name, 0.55, 0.52, (x, y, 0.55))
        w.parent = root
    export_glb(os.path.join(OUT, "car_buggy.glb"))


def bruiser():
    reset()
    root = empty("Car")
    loft("Body", [
        (-2.15, 1.02, 0.95, 0.45, 1.12, 0.9),
        (-1.9, 1.08, 1.0, 0.40, 1.22, 0.98),
        (1.95, 1.08, 1.0, 0.40, 1.28, 1.0),
        (2.15, 1.02, 0.95, 0.48, 1.2, 0.95),
    ], "Paint", parent=root, bev=0.06)
    loft("Cabin", [
        (-0.75, 0.92, 0.8, 1.2, 1.32, 1.25),
        (-0.35, 0.92, 0.78, 1.2, 1.9, 1.6),
        (1.05, 0.92, 0.78, 1.2, 1.92, 1.6),
        (1.3, 0.92, 0.8, 1.2, 1.5, 1.4),
    ], "Paint", parent=root, bev=0.05)
    # slit windows
    box("WinF", (1.5, 0.05, 0.22), (0, -0.56, 1.62), "Glass", rot=(0.75, 0, 0), parent=root)
    for x in (-1, 1):
        box("WinS", (0.05, 1.2, 0.2), (x * 0.9, 0.35, 1.68), "Glass", parent=root)
    box("RoofStripe", (0.7, 1.4, 0.04), (0, 0.35, 1.93), "Stripe", parent=root)
    box("HoodStripe", (0.7, 1.2, 0.03), (0, -1.45, 1.2), "Stripe", rot=(-0.04, 0, 0), parent=root)
    # heavy ram bumper
    box("Ram", (2.5, 0.35, 0.55), (0, -2.35, 0.7), "Steel", parent=root, bev=0.05)
    for x in (-0.8, -0.27, 0.27, 0.8):
        box("RamRib", (0.12, 0.3, 0.62), (x, -2.5, 0.7), "Dark", parent=root, bev=0.02)
    box("Grille", (1.5, 0.05, 0.4), (0, -2.17, 0.95), "Dark", parent=root)
    # side armour plates with bolts
    for x in (-1, 1):
        box("Armor", (0.08, 2.4, 0.5), (x * 1.13, 0.1, 0.8), "Steel", parent=root, bev=0.02)
        for y in (-0.9, -0.3, 0.3, 0.9):
            cyl("Bolt", 0.04, 0.05, (x * 1.18, y, 0.95), "Dark", axis="X", seg=6, parent=root)
        for y in (-1.35, 1.35):
            box("Arch", (0.3, 1.25, 0.18), (x * 1.08, y, 1.08), "Dark", rot=(0, x * 0.2, 0), parent=root, bev=0.04)
        tube("Stack", (x * 0.8, 1.6, 1.25), (x * 0.8, 1.6, 2.1), 0.07, "Steel", root)
    box("RearBumper", (2.3, 0.3, 0.35), (0, 2.25, 0.62), "Dark", parent=root, bev=0.03)
    cyl("Spare", 0.42, 0.28, (0, 2.3, 1.15), "Rubber", axis="Y", seg=20, parent=root)
    for x in (-0.65, 0.65):
        box("HeadL", (0.36, 0.06, 0.16), (x, -2.17, 1.0), "LightFront", parent=root)
        box("TailL", (0.3, 0.05, 0.14), (x, 2.16, 1.05), "LightRear", parent=root)
    box("LightBar", (1.3, 0.14, 0.1), (0, -0.55, 1.98), "Dark", parent=root)
    for x in (-0.45, -0.15, 0.15, 0.45):
        cyl("Spot", 0.07, 0.06, (x, -0.63, 1.98), "LightFront", axis="Y", seg=10, parent=root)
    weapons(root, 1.94)
    for name, x, y in (("Wheel_FL", -1.08, -1.35), ("Wheel_FR", 1.08, -1.35), ("Wheel_RL", -1.08, 1.35), ("Wheel_RR", 1.08, 1.35)):
        w = wheel(name, 0.58, 0.5, (x, y, 0.58))
        w.parent = root
    export_glb(os.path.join(OUT, "car_bruiser.glb"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    buggy()
    bruiser()
