"""Builds Buggy and Bruiser car models -> assets/models/car_<type>.glb

Run:  python tools/assets/make_cars.py      (needs `pip install bpy`, Blender 5.x)
Node names the game relies on: Wheel_FL/FR/RL/RR, Weapon_blaster, Weapon_pulse.
Front of the car = -Y in Blender (= +Z in Godot).
"""
import math
import os
import sys
sys.path.insert(0, os.path.dirname(__file__))
import bpy
from blender_lib import (reset, box, cyl, tube, export_glb, body_loft, cut_wheel_wells, arch_flare,
                         wheel2, smooth_sharp, apply_modifiers, lathe)

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models")


def empty(name, parent=None, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.parent = parent
    e.location = loc
    return e


def weapons(root, z, y=0.1):
    """Roof turrets; the game shows the equipped one. Barrels point to -Y (front)."""
    bl = empty("Weapon_blaster", root, (0, y, z))
    cyl("bl_ring", 0.3, 0.1, (0, 0, 0.05), "Dark", axis="Z", seg=20, parent=bl, bev=0.015)
    box("bl_house", (0.44, 0.62, 0.24), (0, 0.02, 0.24), "Steel", parent=bl, bev=0.05)
    box("bl_ammo", (0.2, 0.3, 0.2), (0.3, 0.1, 0.22), "Dark", parent=bl, bev=0.03)
    box("bl_sight", (0.08, 0.2, 0.08), (0, 0.0, 0.4), "Dark", parent=bl, bev=0.015)
    for x in (-0.1, 0.1):
        cyl("bl_barrel", 0.045, 0.8, (x, -0.68, 0.26), "Dark", axis="Y", seg=10, parent=bl)
        cyl("bl_shroud", 0.07, 0.3, (x, -0.45, 0.26), "Steel", axis="Y", seg=10, parent=bl)
        cyl("bl_tip", 0.06, 0.07, (x, -1.1, 0.26), "Glow", axis="Y", seg=10, parent=bl)
    pu = empty("Weapon_pulse", root, (0, y, z))
    cyl("pu_ring", 0.36, 0.1, (0, 0, 0.05), "Dark", axis="Z", seg=20, parent=pu, bev=0.015)
    cyl("pu_drum", 0.27, 0.7, (0, 0.05, 0.38), "Steel", axis="Y", seg=18, parent=pu, bev=0.03)
    box("pu_fin", (0.06, 0.5, 0.2), (0, 0.1, 0.68), "Dark", parent=pu, bev=0.02)
    cyl("pu_barrel", 0.12, 0.75, (0, -0.65, 0.38), "Dark", axis="Y", seg=14, parent=pu)
    for k, yy in enumerate((-0.4, -0.66, -0.92)):
        cyl("pu_coil%d" % k, 0.165, 0.07, (0, yy, 0.38), "Glow", axis="Y", seg=16, parent=pu)
    cyl("pu_muzzle", 0.15, 0.12, (0, -1.05, 0.38), "Steel", axis="Y", seg=14, parent=pu)


def louvres(root, y0, n, z, width, pitch=0.13, slope=0.0):
    for i in range(n):
        box("Louvre", (width, 0.07, 0.035), (0, y0 + i * pitch, z + i * pitch * slope), "Dark", rot=(0.5, 0, 0), parent=root)


def buggy():
    reset()
    root = empty("Car")
    R = 0.56
    wells = [(-1.05, -1.28, R), (1.05, -1.28, R), (-1.05, 1.32, R), (1.05, 1.32, R)]
    body = body_loft("Body", [
        (-2.05, 0.55, 0.52, 0.62, 0.70, 0.42),
        (-1.97, 0.74, 0.44, 0.66, 0.77, 0.58),
        (-1.30, 0.90, 0.36, 0.74, 0.88, 0.72),
        (-0.55, 0.94, 0.33, 0.80, 0.95, 0.80),
        (0.60, 0.95, 0.33, 0.83, 0.98, 0.82),
        (1.35, 0.95, 0.35, 0.86, 1.02, 0.80),
        (1.95, 0.84, 0.44, 0.84, 0.98, 0.68),
        (2.05, 0.66, 0.52, 0.80, 0.92, 0.52),
    ], parent=root, crease=0.45)
    cut_wheel_wells(body, wells, R + 0.12)
    # wrap-around canopy (glass) with painted roof + stripe
    canopy = body_loft("Canopy", [
        (-0.80, 0.74, 0.88, 0.92, 0.95, 0.60),
        (-0.72, 0.76, 0.88, 0.98, 1.02, 0.64),
        (-0.15, 0.74, 0.88, 1.20, 1.40, 0.60),
        (0.70, 0.72, 0.88, 1.22, 1.42, 0.58),
        (1.18, 0.70, 0.88, 1.02, 1.08, 0.56),
        (1.26, 0.66, 0.88, 0.96, 1.00, 0.52),
    ], parent=root, two_tone=False, mats=("Glass", "Stripe", "Dark"), stripe_hw=0.0001)
    apply_modifiers(canopy)
    smooth_sharp(canopy, 45)
    roof = body_loft("Roof", [
        (-0.22, 0.60, 1.385, 1.40, 1.425, 0.52),
        (-0.12, 0.64, 1.39, 1.41, 1.44, 0.56),
        (0.68, 0.62, 1.41, 1.43, 1.46, 0.54),
        (0.80, 0.58, 1.40, 1.42, 1.445, 0.50),
    ], parent=root, two_tone=False, stripe_hw=0.25, subsurf=1)
    apply_modifiers(roof)
    smooth_sharp(roof, 45)
    # pillars
    for x in (-1, 1):
        tube("PillarA", (x * 0.74, -0.74, 0.95), (x * 0.6, -0.16, 1.41), 0.035, "Paint", root)
        tube("PillarC", (x * 0.58, 0.74, 1.42), (x * 0.68, 1.2, 1.02), 0.035, "Paint", root)
    # exo-cage: the Buggy's open-frame signature
    rr = 0.04
    for x in (-0.84, 0.84):
        tube("CageF", (x, -0.9, 0.9), (x * 0.9, -0.2, 1.52), rr, "Steel", root)
        tube("CageT", (x * 0.9, -0.2, 1.52), (x * 0.9, 0.85, 1.54), rr, "Steel", root)
        tube("CageR", (x * 0.9, 0.85, 1.54), (x, 1.75, 1.0), rr, "Steel", root)
        tube("CageB", (x * 0.9, 0.3, 1.53), (x * 1.02, 0.3, 0.86), rr, "Steel", root)
    for y, z in ((-0.2, 1.52), (0.85, 1.54)):
        tube("CageX", (-0.76, y, z), (0.76, y, z), rr, "Steel", root)
    # fender flares + mud flaps
    for i, (x, y, z) in enumerate(wells):
        s = 1 if x > 0 else -1
        arch_flare("Flare%d" % i, (x - s * 0.2, y, z), R + 0.1, 0.42, 0.07, "Dark", root, side=s)
    # hood scoop, louvres on the rear deck
    box("Scoop", (0.5, 0.6, 0.1), (0, -1.0, 0.95), "Dark", rot=(-0.1, 0, 0), parent=root, bev=0.04)
    louvres(root, 1.38, 5, 1.03, 0.9)
    for x in (-0.62, 0.62):
        box("SideVent", (0.03, 0.45, 0.16), (x * 1.54, 0.35, 0.62), "Dark", parent=root)
    # bull bar, skid plate, tow hooks
    tube("BullH", (-0.72, -2.22, 0.76), (0.72, -2.22, 0.76), 0.05, "Steel", root)
    tube("BullL", (-0.8, -2.2, 0.46), (0.8, -2.2, 0.46), 0.055, "Steel", root)
    for x in (-0.5, 0.5):
        tube("BullV", (x, -2.21, 0.42), (x, -2.22, 0.8), 0.045, "Steel", root)
        tube("BullS", (x, -2.21, 0.6), (x, -1.95, 0.62), 0.04, "Steel", root)
    box("Skid", (1.45, 0.55, 0.06), (0, -1.98, 0.37), "Steel", rot=(0.32, 0, 0), parent=root, bev=0.015)
    # lights
    for x in (-0.5, 0.5):
        box("HeadHousing", (0.4, 0.1, 0.17), (x, -2.02, 0.66), "Dark", parent=root, bev=0.03)
        box("HeadL", (0.32, 0.06, 0.1), (x, -2.07, 0.66), "LightFront", parent=root, bev=0.02)
        box("TailL", (0.42, 0.06, 0.09), (x * 0.95, 2.06, 0.84), "LightRear", parent=root, bev=0.02)
    for x in (-0.3, -0.1, 0.1, 0.3):
        cyl("RoofLamp", 0.07, 0.07, (x, -0.27, 1.6), "LightFront", axis="Y", seg=12, parent=root)
        cyl("RoofLampH", 0.085, 0.1, (x, -0.22, 1.6), "Dark", axis="Y", seg=12, parent=root)
    # rear bumper bar, exhausts, wing
    tube("RearBar", (-0.8, 2.18, 0.5), (0.8, 2.18, 0.5), 0.05, "Steel", root)
    for x in (-0.35, 0.35):
        tube("Exhaust", (x, 1.95, 0.5), (x, 2.24, 0.52), 0.065, "Steel", root)
        box("WingPost", (0.05, 0.3, 0.34), (x * 1.6, 1.86, 1.16), "Dark", parent=root, bev=0.012)
    box("Wing", (1.75, 0.45, 0.05), (0, 1.9, 1.34), "Paint", rot=(0.14, 0, 0), parent=root, bev=0.02)
    for x in (-0.875, 0.875):
        box("WingEnd", (0.035, 0.52, 0.26), (x, 1.9, 1.36), "Dark", parent=root, bev=0.01)
    weapons(root, 1.46, 0.3)
    for name, (x, y, z) in zip(("Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"), wells):
        wheel2(name, R, 0.5, (x * 1.03, y, z), parent=root)
    export_glb(os.path.join(OUT, "car_buggy.glb"))


def bruiser():
    reset()
    root = empty("Car")
    R = 0.6
    wells = [(-1.1, -1.4, R), (1.1, -1.4, R), (-1.1, 1.4, R), (1.1, 1.4, R)]
    body = body_loft("Body", [
        (-2.2, 0.92, 0.50, 0.95, 1.08, 0.80),
        (-2.12, 1.04, 0.42, 1.0, 1.16, 0.92),
        (-2.0, 1.08, 0.40, 1.02, 1.2, 0.98),
        (-0.8, 1.1, 0.38, 1.05, 1.24, 1.0),
        (1.9, 1.1, 0.38, 1.08, 1.3, 1.0),
        (2.1, 1.06, 0.42, 1.06, 1.28, 0.94),
        (2.2, 0.94, 0.50, 1.0, 1.2, 0.82),
    ], parent=root, stripe_hw=0.36, subsurf=2, crease=0.9)
    cut_wheel_wells(body, wells, R + 0.12, 0.8)
    cabin = body_loft("Cabin", [
        (-0.95, 0.90, 1.2, 1.28, 1.32, 0.80),
        (-0.86, 0.94, 1.2, 1.4, 1.5, 0.84),
        (-0.4, 0.94, 1.2, 1.7, 1.94, 0.84),
        (1.1, 0.94, 1.2, 1.72, 1.98, 0.84),
        (1.4, 0.92, 1.2, 1.5, 1.6, 0.82),
        (1.48, 0.86, 1.2, 1.36, 1.4, 0.76),
    ], parent=root, two_tone=False, stripe_hw=0.36, crease=0.9)
    apply_modifiers(cabin)
    smooth_sharp(cabin, 45)
    # armoured slit windows
    box("WinF", (1.45, 0.06, 0.2), (0, -0.62, 1.62), "Glass", rot=(0.72, 0, 0), parent=root, bev=0.015)
    for x in (-1, 1):
        box("WinS", (0.06, 1.15, 0.2), (x * 0.925, 0.35, 1.62), "Glass", parent=root, bev=0.015)
        box("WinFrame", (0.05, 1.3, 0.06), (x * 0.93, 0.35, 1.76), "Dark", parent=root)
    # ram bumper
    box("Ram", (2.55, 0.32, 0.6), (0, -2.42, 0.72), "Steel", parent=root, bev=0.06)
    for x in (-0.85, -0.28, 0.28, 0.85):
        box("RamRib", (0.13, 0.26, 0.7), (x, -2.58, 0.72), "Dark", parent=root, bev=0.03)
    box("RamTop", (2.3, 0.12, 0.1), (0, -2.4, 1.08), "Steel", parent=root, bev=0.02)
    box("Grille", (1.45, 0.06, 0.36), (0, -2.2, 0.92), "Dark", parent=root)
    for i in range(5):
        box("GrilleBar", (1.4, 0.04, 0.03), (0, -2.24, 0.78 + i * 0.07), "Steel", parent=root)
    # side armour with bolts, steps
    for x in (-1, 1):
        box("Armor", (0.07, 1.7, 0.5), (x * 1.14, 0.0, 0.82), "Steel", parent=root, bev=0.025)
        for y in (-0.7, -0.25, 0.25, 0.7):
            cyl("Bolt", 0.045, 0.05, (x * 1.18, y, 0.98), "Dark", axis="X", seg=6, parent=root)
            cyl("Bolt2", 0.045, 0.05, (x * 1.18, y, 0.66), "Dark", axis="X", seg=6, parent=root)
        box("Step", (0.22, 1.3, 0.06), (x * 1.2, 0.0, 0.42), "Dark", parent=root, bev=0.015)
        tube("Stack", (x * 0.82, 1.62, 1.3), (x * 0.82, 1.62, 2.2), 0.075, "Steel", root)
        cyl("StackTip", 0.09, 0.14, (x * 0.82, 1.62, 2.22), "Dark", axis="Z", seg=10, parent=root)
    for i, (x, y, z) in enumerate(wells):
        s = 1 if x > 0 else -1
        arch_flare("Flare%d" % i, (x - s * 0.14, y, z), R + 0.1, 0.34, 0.08, "Dark", root, side=s)
    box("RearBumper", (2.35, 0.3, 0.36), (0, 2.3, 0.62), "Dark", parent=root, bev=0.04)
    lathe("Spare", [(0.2, -0.13), (0.4, -0.15), (0.47, -0.1), (0.47, 0.1), (0.4, 0.15), (0.2, 0.13)], "Rubber", seg=24, parent=root).matrix_world = (
        __import__("mathutils").Matrix.Translation((0, 2.36, 1.2)) @ __import__("mathutils").Matrix.Rotation(math.pi / 2, 4, "Z"))
    cyl("SpareHub", 0.2, 0.2, (0, 2.38, 1.2), "Rim", axis="Y", seg=14, parent=root)
    for x in (-0.68, 0.68):
        box("HeadHousing", (0.42, 0.1, 0.22), (x, -2.2, 1.0), "Dark", parent=root, bev=0.03)
        box("HeadL", (0.32, 0.06, 0.14), (x, -2.25, 1.0), "LightFront", parent=root, bev=0.02)
        box("TailL", (0.3, 0.06, 0.16), (x * 1.2, 2.22, 1.1), "LightRear", parent=root, bev=0.02)
    # roof rack with light bar
    box("LightBar", (1.4, 0.16, 0.12), (0, -0.5, 2.04), "Dark", parent=root, bev=0.03)
    for x in (-0.5, -0.17, 0.17, 0.5):
        cyl("Spot", 0.075, 0.06, (x, -0.6, 2.04), "LightFront", axis="Y", seg=12, parent=root)
    for x in (-0.78, 0.78):
        tube("Rack", (x, -0.3, 2.02), (x, 1.2, 2.04), 0.03, "Steel", root)
    box("HoodVent", (0.9, 0.7, 0.06), (0, -1.45, 1.27), "Dark", parent=root, bev=0.02)
    weapons(root, 2.0, 0.45)
    for name, (x, y, z) in zip(("Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"), wells):
        wheel2(name, R, 0.5, (x * 1.02, y, z), parent=root)
    export_glb(os.path.join(OUT, "car_bruiser.glb"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    buggy()
    bruiser()
