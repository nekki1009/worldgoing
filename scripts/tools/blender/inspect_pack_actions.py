"""Print the armature, its pose-bone rest data and the actions of a character pack .blend (read only).

Run: run_blender.ps1 --background <pack.blend> --python scripts/tools/blender/inspect_pack_actions.py
"""
import bpy

arms = [o for o in bpy.data.objects if o.type == 'ARMATURE']
print("ARMATURES", [(a.name, len(a.data.bones)) for a in arms])
for a in arms:
    print("ARM", a.name, "action", a.animation_data.action.name if a.animation_data and a.animation_data.action else None,
          "loc", tuple(round(v, 3) for v in a.location), "rot", tuple(round(v, 3) for v in a.rotation_euler))
    for b in a.data.bones:
        if b.name.startswith("J_Bip"):
            print("BONE", b.name, "parent", b.parent.name if b.parent else None,
                  "head", tuple(round(v, 3) for v in b.head_local), "tail", tuple(round(v, 3) for v in b.tail_local))
print("ACTIONS", [(act.name, round(act.frame_range[1] - act.frame_range[0], 1), len(act.fcurves)) for act in bpy.data.actions])
print("SCENE fps", bpy.context.scene.render.fps)
