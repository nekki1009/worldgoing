"""Four additive neutral eye anatomies; never bake emotion shape keys."""
import argparse
import json
import math
import shutil
import sys
import uuid
from pathlib import Path
import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).parent))
from medieval_cloth_export import append_cloth

OUT = ROOT / 'output/neutral_faces_20260918'
WORK = ROOT / 'assets/characters/human/q35/neutral_faces'
STYLES = {5: ('round', .92, 1.17, 0.0), 6: ('almond', 1.16, .86, 0.0),
          7: ('slim', 1.10, .66, .001), 8: ('wide_set', .96, 1.02, .006)}


def falloff(value, inner, outer):
    t = np.clip((outer-value)/(outer-inner), 0, 1)
    return t*t*(3-2*t)


def make_faces():
    source = bpy.data.objects['Face_Standard_01']
    assert source.data.shape_keys is None, 'Use the published neutral face, not emotion keys'
    points = np.array([tuple(source.matrix_world @ v.co) for v in source.data.vertices])
    regions = {}
    for index, mat in enumerate(source.data.materials):
        regions[mat.name.lower()] = sorted({v for poly in source.data.polygons if poly.material_index == index for v in poly.vertices})
    whites = points[next(ids for name, ids in regions.items() if 'eyewhite' in name)]
    mid = (whites[:, 0].min()+whites[:, 0].max())/2
    half = whites[whites[:, 0] > mid]
    cx = (half[:, 0].min()+half[:, 0].max())/2-mid
    cz = (half[:, 2].min()+half[:, 2].max())/2
    x = points[:, 0]-mid
    sign = np.where(x >= 0, 1, -1)
    dx = np.abs(x)-cx
    dz = points[:, 2]-cz
    # Keep the eyelid boundary and adjoining skin on the SAME continuous map.
    # Fall off before the nose, cheek silhouette, forehead and mouth.
    influence = falloff(np.abs(dx), .029, .055)*falloff(np.abs(dz), .018, .040)
    influence *= falloff(dz, .017, .026) # Keep skin under the unchanged brow planes intact.
    influence *= 1-falloff(np.abs(x), .011, .019)
    influence *= falloff(points[:, 1]-whites[:, 1].max(), .007, .030)
    protected = set()
    irises = set()
    for name, ids in regions.items():
        if 'brow' in name or 'mouth' in name: protected.update(ids)
        if 'eyeiris' in name or 'eyehighlight' in name: irises.update(ids)
    influence[list(protected)] = 0
    inv = source.matrix_world.inverted()
    parts = []
    report = {'mid': mid, 'eye_center_abs_x': cx, 'eye_center_z': cz, 'styles': []}
    for number, (style, width, height, spacing) in STYLES.items():
        target = points.copy()
        target[:, 0] += sign*(dx*(width-1)+spacing)*influence
        target[:, 2] += dz*(height-1)*influence
        # Pupil/iris diameter and gaze stay constant; eyelids define the opening.
        indices = list(irises)
        target[indices] = points[indices]
        target[indices, 0] += sign[indices]*spacing
        obj = source.copy()
        obj.data = source.data.copy()
        obj.name = f'Face_Standard_{number:02d}'
        obj.data.name = obj.name+'Mesh'
        bpy.context.scene.collection.objects.link(obj)
        for index, (vertex, point) in enumerate(zip(obj.data.vertices, target)):
            if not np.array_equal(point, points[index]): vertex.co = inv @ Vector(point)
        obj.data.update()
        obj['worldgoing_component_slot'] = 'face'
        obj['worldgoing_visual_id'] = f'face_standard_{number:02d}'
        obj['worldgoing_neutral_eye_style'] = style
        obj.hide_render = obj.hide_viewport = True
        assert np.array_equal(target[list(protected)], points[list(protected)])
        report['styles'].append({'id': obj['worldgoing_visual_id'], 'style': style, 'width': width, 'height': height,
                                 'spacing': spacing, 'changed_vertices': int(np.count_nonzero(np.any(target != points, axis=1))),
                                 'protected_brow_mouth_vertices': len(protected), 'iris_size_unchanged': True})
        parts.append(obj)
    return parts, report


def reset(arm):
    arm.animation_data.action = None
    for track in arm.animation_data.nla_tracks: track.mute = True
    for bone in arm.pose.bones: bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


def save(sex):
    temp = ROOT / f'.godot-temp/neutral_faces_{sex}_{uuid.uuid4().hex}.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(temp))
    target = WORK / f'neutral_faces_{sex}.blend'
    shutil.copy2(temp, target)
    assert target.stat().st_size == temp.stat().st_size
    temp.unlink()


def preview(sex, arm, parts):
    reset(arm)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
    scene.render.resolution_x = scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    if scene.world is None: scene.world = bpy.data.worlds.new('NeutralFaceReviewWorld')
    scene.world.color = (.22, .22, .22)
    data = bpy.data.cameras.new('NeutralFaceReview')
    camera = bpy.data.objects.new('NeutralFaceReview', data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    data.type = 'ORTHO'
    data.ortho_scale = .34
    source = bpy.data.objects['Face_Standard_01']
    points = [source.matrix_world @ v.co for v in source.data.vertices]
    center = Vector((0, -.03, (min(p.z for p in points)+max(p.z for p in points))/2))
    for obj in bpy.data.objects:
        if obj.type == 'LIGHT': obj.hide_render = True
    for name, loc, energy, size in [('key',(-1,-2,3),180,3),('fill',(1,-1,1),90,3)]:
        light_data = bpy.data.lights.new('FaceReview_'+name, 'AREA')
        light_data.energy = energy; light_data.shape = 'DISK'; light_data.size = size
        light = bpy.data.objects.new('FaceReview_'+name, light_data)
        scene.collection.objects.link(light); light.location = loc
        light.rotation_euler = (center-light.location).to_track_quat('-Z','Y').to_euler()
    for face in parts:
        for obj in bpy.data.objects:
            if obj.type == 'MESH': obj.hide_render = obj != face
        face.hide_viewport = False
        for label, angle in [('front',0),('side',90),('back',180),('threequarter',35)]:
            a = math.radians(angle)
            camera.location = center+Vector((math.sin(a)*3,-math.cos(a)*3,0))
            camera.rotation_euler = (center-camera.location).to_track_quat('-Z','Y').to_euler()
            scene.render.filepath = str(OUT / f'{sex}_{face.name[-2:]}_shape_{label}.png')
            bpy.ops.render.render(write_still=True)


def export(sex, arm, parts):
    reset(arm)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [arm]+parts:
        obj.hide_viewport = False; obj.hide_set(False); obj.select_set(True)
    subset = WORK / f'subset_{sex}.glb'
    bpy.ops.export_scene.gltf(filepath=str(subset), export_format='GLB', use_selection=True,
                             export_animations=False, export_skins=True, export_morph=False, export_apply=False)
    append_cloth(OUT/f'baseline/standard_anime_{sex}_character_pack.glb', subset, WORK/f'candidate_{sex}.glb', {}, 'Face_Standard_')
    meta = json.loads((OUT/f'baseline/standard_anime_{sex}_character_pack.json').read_text(encoding='utf-8'))
    meta['parts']['face'] += [obj.name for obj in parts]
    meta['neutral_faces'] = {'ids': [obj['worldgoing_visual_id'] for obj in parts], 'expression': 'neutral',
                             'reference': 'output/neutral_faces_20260918/reference/neutral_eyes_board.png'}
    (WORK/f'candidate_{sex}.json').write_text(json.dumps(meta, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sex', choices=['male','female'], required=True)
    parser.add_argument('--stage', choices=['gray','preview','export'], required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    bpy.context.preferences.filepaths.save_version = 0
    source = OUT/f'baseline/standard_anime_{args.sex}_character_pack.blend' if args.stage == 'gray' else WORK/f'neutral_faces_{args.sex}.blend'
    bpy.ops.wm.open_mainfile(filepath=str(source))
    arm = bpy.data.objects['Armature']
    if args.stage == 'gray':
        assert 'Face_Standard_05' not in bpy.data.objects, 'Use export to preserve authored edits'
        parts, report = make_faces()
        (OUT/f'{args.sex}_anatomy.json').write_text(json.dumps(report, indent=2))
        save(args.sex)
        preview(args.sex, arm, parts)
    else:
        parts = [bpy.data.objects[f'Face_Standard_{i:02d}'] for i in STYLES]
        if args.stage == 'preview': preview(args.sex, arm, parts)
        else: export(args.sex, arm, parts)
    print('NEUTRAL_FACES_STAGE_PASS', args.sex, args.stage, len(parts), flush=True)


if __name__ == '__main__': main()
