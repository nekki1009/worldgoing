"""Rebuild only the logistics props. Metres, Blender -Y = Godot +Z forward.

The horse is a read-only external asset composed by the offline Godot baker;
this source never rewrites horse/character meshes, rigs or animations.
"""
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "assets/vehicles/logistics/v1"
HORSE = "res://assets/mounts/horse/standard_horse_pack.glb"


def material(name, rgb, metallic=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = (*rgb, 1)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = .73
    return mat


def finish(obj, name, mat, parent=None):
    obj.name = name
    if mat:
        obj.data.materials.append(mat)
    if parent:
        bpy.context.view_layer.update()
        matrix = obj.matrix_world.copy()
        obj.parent = parent
        obj.matrix_world = matrix
    return obj


def box(name, pos, size, mat, parent=None, bevel=.012):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        modifier = obj.modifiers.new("WornEdges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.modifiers.new("WeightedNormals", "WEIGHTED_NORMAL")
    return finish(obj, name, mat, parent)


def rod(name, start, end, radius, mat, parent=None, vertices=12):
    start, end = Vector(start), Vector(end)
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius,
                                      depth=(end-start).length, location=(start+end)*.5)
    obj = bpy.context.object
    obj.rotation_euler = (end-start).to_track_quat("Z", "Y").to_euler()
    return finish(obj, name, mat, parent)


def line(name, points, radius, mat):
    for i in range(len(points)-1):
        rod(name + "_%02d" % i, points[i], points[i+1], radius, mat)


def wheel(name, x, y, radius, wood, iron, hub):
    pivot = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(pivot)
    pivot.location = (x, y, radius)
    for ring_radius, thickness, mat in [(radius-.033, .039, wood), (radius, .018, iron)]:
        bpy.ops.mesh.primitive_torus_add(major_segments=32, minor_segments=8,
            location=pivot.location, rotation=(0, math.pi/2, 0),
            major_radius=ring_radius, minor_radius=thickness)
        finish(bpy.context.object, name + "_Rim", mat, pivot)
    for i in range(10):
        a = i*math.tau/10
        rod(name + "_Spoke%02d" % i, (x,y,radius),
            (x,y+math.cos(a)*(radius-.06),radius+math.sin(a)*(radius-.06)), .021, wood, pivot, 8)
    rod(name+"_Hub", (x-.105,y,radius), (x+.105,y,radius), .081, hub, pivot)
    # One slightly pale spoke makes actual rotation legible at map scale.
    return pivot


def crate(name, pos, size, wood, trim):
    x,y,z = pos
    w,d,h = size
    for i in range(4):
        box(name+"_Board%d" % i, (x,y,z+h*(i+.5)/4), (w,d,h/4-.009), wood)
    for dx in [-w*.37,w*.37]:
        box(name+"_TopBrace", (x+dx,y,z+h+.02), (.055,d+.025,.045), trim)
        for dy in [-d*.5-.014,d*.5+.014]:
            box(name+"_Brace", (x+dx,y+dy,z+h*.5), (.052,.032,h+.06), trim)


def sack(name, pos, scale, cloth, rope):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, location=pos)
    obj = bpy.context.object
    obj.scale = scale
    finish(obj,name,cloth)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    x,y,z=pos
    rod(name+"_Neck", (x,y,z+scale[2]*.83), (x,y,z+scale[2]*1.14), .065, cloth)
    bpy.ops.mesh.primitive_torus_add(major_segments=16,minor_segments=6,
        location=(x,y,z+scale[2]*.98),major_radius=.066,minor_radius=.014)
    finish(bpy.context.object,name+"_Tie",rope)


def build(kind):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    wood = [material("AgedOak%d"%i,(.29+i*.027,.135+i*.014,.045+i*.006)) for i in range(4)]
    dark = material("EndGrain",(.14,.065,.023))
    iron = material("ForgedIron",(.10,.12,.13),.7)
    cloth = material("LinenSack",(.58,.46,.27))
    leather = material("DraftLeather",(.095,.045,.019))
    rope = material("HempRope",(.32,.24,.12))
    wagon = kind == "wagon"
    width,length,radius = (1.45,2.05,.46) if wagon else (1.05,1.35,.39)
    floor = radius+.20
    axle_ys = [-.70,.70] if wagon else [0]
    for y in axle_ys:
        rod("Axle", (-width*.5-.20,y,radius), (width*.5+.20,y,radius), .057,iron)
        for side in [-1,1]:
            wheel("Wheel_%s_%s"%("L" if side<0 else "R",str(y).replace('.','_')),
                  side*(width*.5+.13),y,radius,wood[1],iron,dark)
    for x in [-width*.35,width*.35]:
        box("ChassisBeam",(x,0,floor-.07),(.10,length+.18,.14),dark)
    for i in range(7):
        box("FloorPlank%02d"%i,((i-3)*width/7,0,floor), (width/7-.010,length,.070),wood[i%4])
    # Continuous plank walls with gaps, corner stakes and external iron straps.
    for level in range(3):
        z=floor+.13+level*.155
        for side in [-1,1]:
            box("SidePlank",(side*width*.5,0,z),(.065,length,.137),wood[(level+1)%4])
            box("EndPlank",(0,side*length*.5,z),(width,.065,.137),wood[level%4])
    for x in [-width*.5,width*.5]:
        for y in [-length*.5,length*.5]:
            box("CornerStake",(x,y,floor+.27),(.092,.092,.61),dark)
        for y in [-length*.32,length*.32]:
            box("SideIronStrap",(x*1.05,y,floor+.28),(.018,.048,.57),iron,bevel=.004)
    if wagon:
        for side in [-1,1]:
            # Two long shafts flank, rather than intersect, the original horse.
            line("Shaft",[(side*.54,-.78,floor-.04),(side*.50,-1.65,.90),
                 (side*.43,-3.30,.98)],.049,wood[0])
            # Traces transmit load from breast collar to chassis, not the bridle.
            line("Trace",[(side*.49,-.94,.94),(side*.39,-2.70,1.05),
                 (side*.33,-3.18,1.13)],.020,leather)
        # Breastcollar and over-withers strap, built around measured horse bounds.
        line("BreastCollar",[(-.32,-3.18,1.23),(-.35,-3.23,1.05),(0,-3.31,.94),
             (.35,-3.23,1.05),(.32,-3.18,1.23)],.045,leather)
        line("WithersStrap",[(-.32,-3.17,1.23),(-.33,-2.97,1.51),(0,-2.89,1.67),
             (.33,-2.97,1.51),(.32,-3.17,1.23)],.031,leather)
        for side in [-1,1]:
            line("DrivingRein",[(side*.13,-3.93,1.62),(side*.36,-3.23,1.48),
                 (side*.37,-1.17,1.19)],.012,leather)
        crate("CrateA",(-.32,-.38,floor+.06),(.56,.68,.59),wood[2],dark)
        crate("CrateB",(.31,.39,floor+.06),(.55,.57,.52),wood[0],dark)
        sack("GrainA",(-.29,.48,floor+.38),(.26,.29,.34),cloth,rope)
        sack("GrainB",(-.32,-.38,floor+.94),(.25,.29,.29),cloth,rope)
    else:
        for side in [-1,1]:
            line("PushHandle",[(side*.42,.37,floor-.04),(side*.40,1.49,.84)],.046,wood[0])
            rod("LeatherGrip",(side*.40,1.23,.80),(side*.40,1.49,.84),.054,leather)
        crate("SupplyCrate",(-.17,-.22,floor+.06),(.58,.58,.48),wood[2],dark)
        sack("GrainA",(.19,.28,floor+.36),(.27,.28,.32),cloth,rope)
        sack("GrainB",(.23,-.23,floor+.76),(.21,.23,.23),cloth,rope)
    bpy.context.scene["forward"]="Blender -Y / Godot +Z"
    bpy.context.scene["ground_anchor"]="chassis centre at ground origin"
    bpy.context.scene["horse_source"]=HORSE if wagon else ""
    bpy.context.scene["horse_godot_offset"]=[0.,0.,2.6] if wagon else [0.,0.,0.]
    bpy.context.view_layer.update()
    assert len([o for o in bpy.data.objects if o.name.startswith("Wheel_") and o.type=="EMPTY"]) == (4 if wagon else 2)
    assert all(v.co.length < 20 for obj in bpy.data.objects if obj.type=="MESH" for v in obj.data.vertices)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(kind+".blend")))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(kind+".glb")),export_format="GLB",
        export_animations=False,export_skins=False,export_morph=False)
    return {"kind":kind,"floor_metres":floor,"wheel_radius_metres":radius,
            "body_width_metres":width,"body_length_metres":length,
            "horse_source":HORSE if wagon else "", "horse_offset":[0,0,2.6] if wagon else [0,0,0]}


if __name__ == "__main__":
    OUT.mkdir(parents=True,exist_ok=True)
    rows=[build(kind) for kind in ["cart","wagon"]]
    (OUT/"source_manifest.json").write_text(json.dumps({"version":1,"units":"metres",
        "ground_anchor":[0,0,0],"vehicles":rows},indent=2)+"\n",encoding="utf-8")
    print("LOGISTICS VEHICLE SOURCE PASS",flush=True)
