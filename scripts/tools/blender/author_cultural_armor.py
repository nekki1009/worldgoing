"""Additive cultural armor source. Explicit build; export preserves manual edits."""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).parent))
from author_chinese_leather_mingguang import Fitting, surface as fitted_surface, mesh_part, tube
from author_western_plate import torso_weights, limb_surface, source_weights
from author_medieval_shoes import last, mesh as shoe_mesh
from author_chinese_leather_boots import reweight as reweight_boots
from author_cloth_hats import forms as head_forms
from build_standard_anime_male_character_pack import copy_mesh
from ensure_morph_uv import projected_uv
from repair_character_audit import reset_rig
from load_authored_cultural_armor import PREFIXES

BASE = ROOT / 'output/equipment_matrix_20260918/baseline'
WORK = ROOT / 'assets/characters/human/q35/equipment_matrix'
QA = ROOT / 'reports/output/equipment_matrix_20260918/armor'
REFERENCE = ROOT / 'output/equipment_matrix_20260918/reference/armor_reference.png'


def tag(obj):
    prefix = component(obj)
    obj['worldgoing_component_slot'] = prefix.split('_')[0].lower()
    obj['worldgoing_visual_id'] = prefix.lower()
    obj['cultural_armor_revision'] = 1
    obj.hide_viewport = obj.hide_render = False
    obj.hide_set(False)
    return obj


def material(label, color, metal=0, rough=.8, weave=False):
    name = 'CulturalArmor_' + label
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Metallic'].default_value = metal
    shader.inputs['Roughness'].default_value = rough
    # Native, packed PBR weave/grain maps; no dependency on reference-image pixels.
    if weave or label == 'Leather':
        y, x = np.mgrid[:128, :128]
        noise = np.random.default_rng(1835).normal(0, .025, (128, 128))
        grain = noise + (.045 * np.sin(x * math.pi / 2) * np.sin(y * math.pi / 2) if weave else 0)
        pixels = np.ones((128, 128, 4), dtype=np.float32)
        pixels[:, :, :3] = np.clip(np.array(color)[None, None, :] * (1 + grain[:, :, None]), 0, 1)
        image = bpy.data.images.new(name + '_Color', width=128, height=128)
        image.pixels.foreach_set(pixels.ravel())
        image.pack()
        node = mat.node_tree.nodes.new('ShaderNodeTexImage')
        node.image = image
        mat.node_tree.links.new(node.outputs['Color'], shader.inputs['Base Color'])
    return mat


def surface(name, fn, mat, fit, bone='J_Bip_C_UpperChest', weights=None, rows=6, cols=24, thickness=.004):
    return tag(fitted_surface(name, fn, rows, cols, mat, fit, bone, weights, thickness))


def clone(source, name, replacement=None):
    obj = tag(copy_mesh(source, name, '', ''))
    obj['cultural_source_mesh'] = source.name
    if replacement:
        obj.data.materials.clear()
        obj.data.materials.append(replacement)
        for polygon in obj.data.polygons:
            polygon.material_index = 0
    if not obj.data.uv_layers:
        assert not any(m and m.use_nodes and any(n.type == 'TEX_IMAGE' for n in m.node_tree.nodes)
                       for m in obj.data.materials), source.name
        coords = projected_uv(np.array([tuple(v.co) for v in obj.data.vertices]))
        uv = obj.data.uv_layers.new(name='SolidMaterialUV')
        for loop in obj.data.loops:
            uv.data[loop.index].uv = coords[loop.vertex_index]
        obj['cultural_uv_added'] = True
    return obj


def cords(name, paths, mat, fit, weights, radius=.0018):
    vertices, faces = [], []
    for path in paths:
        offset = len(vertices)
        for i, point in enumerate(path):
            tangent = (path[min(i + 1, len(path) - 1)] - path[max(0, i - 1)]).normalized()
            axis = Vector((1, 0, 0)) if abs(tangent.x) < .9 else Vector((0, 1, 0))
            a = tangent.cross(axis).normalized()
            b = tangent.cross(a).normalized()
            vertices.extend(point + radius * (a * math.cos(j * math.tau / 6) + b * math.sin(j * math.tau / 6)) for j in range(6))
        faces.extend((offset + i * 6 + j, offset + i * 6 + (j + 1) % 6,
                      offset + (i + 1) * 6 + (j + 1) % 6, offset + (i + 1) * 6 + j)
                     for i in range(len(path) - 1) for j in range(6))
        faces.extend((tuple(offset + j for j in reversed(range(6))),
                      tuple(offset + (len(path) - 1) * 6 + j for j in range(6))))
    return tag(mesh_part(name, vertices, faces, mat, fit, weights=weights, thickness=0))


def japanese_armor(fit, plate, padding, lace):
    prefix = 'Armor_Japanese_Leather_01_'
    parts = [clone(bpy.data.objects['Armor_Iron_01_UnderTunic'], prefix + 'UnderShirt', padding),
             clone(bpy.data.objects['Armor_Iron_01_Underlayer_Pants'], prefix + 'UnderPants', padding)]
    low, high = fit.hip + .07, fit.neck - .09
    for tier in range(6):
        bottom = low + (high - low) * tier / 6
        top = low + (high - low) * (tier + 1) / 6 + .009
        def panel(u, v, bottom=bottom, top=top):
            return fit.torso(math.tau * u, bottom + (top - bottom) * v, .024 + .003 * (1 - v))
        parts.append(surface(prefix + f'Do_Lame_{tier}', panel, plate, fit,
                             weights=lambda p: torso_weights(fit, p), rows=3, cols=48, thickness=.005))
        paths = []
        for angle in np.linspace(0, math.tau, 25)[:-1]:
            paths.append([fit.torso(float(angle + .012 * math.sin(t * math.pi)),
                                   bottom + .007 + t * (top - bottom - .014), .031) for t in np.linspace(0, 1, 5)])
        parts.append(cords(prefix + f'Do_Lacing_{tier}', paths, lace, fit, lambda p: torso_weights(fit, p)))
    # Native torso straps join the breastplate to the backplate across the shoulders.
    for side, sign in (('L', 1), ('R', -1)):
        shoulder = fit.bone('J_Bip_' + side + '_UpperArm')
        neck = fit.bone('J_Bip_C_Neck')
        def strap(u, v, sign=sign, shoulder=shoulder):
            angle = -math.pi / 2 + math.pi * v
            x = sign * (abs(shoulder.x) * .55 + (u - .5) * .037)
            point = Vector((x, neck.y + .086 * math.sin(angle), high + .053 * math.cos(angle)))
            hit, normal, _, _ = fit.bvh.find_nearest(point)
            return hit + normal * .027 if hit is not None else point
        parts.append(surface(prefix + 'Watagami_' + side, strap, plate, fit,
                             weights=lambda p: torso_weights(fit, p), rows=16, cols=3, thickness=.005))
        upper = 'J_Bip_' + side + '_UpperArm'
        elbow = fit.bone('J_Bip_' + side + '_LowerArm')
        length = (elbow - shoulder).length
        for tier in range(4):
            def sode(u, v, tier=tier, shoulder=shoulder, elbow=elbow, sign=sign, length=length):
                t = .04 + tier * .18 + v * .22
                center = shoulder.lerp(elbow, t)
                angle = -.08 + (math.pi + .16) * u
                direction = Vector((0, -math.cos(angle), math.sin(angle)))
                hit, _, _, _ = fit.bvh.ray_cast(center + direction * .20, -direction, .25)
                radius = max(.035, (hit - center).dot(direction) if hit is not None else .055)
                return center + direction * (radius + .025 + .005 * v)
            part = surface(prefix + f'Sode_{tier}_{side}', sode, plate, fit, upper, rows=3, cols=18, thickness=.005)
            parts.append(part)
            paths = [[sode(float(u), float(v)) + Vector((0, 0, .004)) for v in np.linspace(.12, .84, 5)]
                     for u in (.18, .40, .60, .82)]
            parts.append(cords(prefix + f'SodeLacing_{tier}_{side}', paths, lace, fit, lambda p, upper=upper: {upper: 1}))
        lower, hand = 'J_Bip_' + side + '_LowerArm', 'J_Bip_' + side + '_Hand'
        fn = limb_surface(fit, lower, hand, .15, .85, .012, angular=math.pi * .92)
        parts.append(surface(prefix + 'Kote_' + side, fn, plate, fit, lower, rows=8, cols=24))
    # Six divided skirts. Weights come from the corresponding thigh/hip skin surface.
    top, bottom = fit.hip + .067, fit.knee + (fit.hip - fit.knee) * .30
    for sector in range(6):
        angle = (sector + .5) * math.tau / 6
        side = 'L' if math.sin(angle) > 0 else 'R'
        def weights(point, side=side):
            native = {n: w for n, w in fit.weights(point).items() if n in ('J_Bip_C_Hips', 'J_Bip_' + side + '_UpperLeg')}
            total = sum(native.values())
            assert total > 0, ('kusazuri weights', point, side)
            return {n: w / total for n, w in native.items()}
        for tier in range(4):
            ztop = top - (top - bottom) * tier / 4
            zbottom = top - (top - bottom) * (tier + 1) / 4 - .007
            def panel(u, v, angle=angle, ztop=ztop, zbottom=zbottom):
                a = angle + (u - .5) * math.radians(54)
                z = ztop + (zbottom - ztop) * v
                p = fit.torso(a, fit.hip + .033, .021)
                flare = .020 * (top - z) / (top - bottom)
                p += Vector((math.sin(a) * flare, -math.cos(a) * flare, 0))
                p.z = z
                return p
            parts.append(surface(prefix + f'Kusazuri_{sector}_{tier}', panel, plate, fit,
                                 weights=weights, rows=3, cols=8, thickness=.005))
            paths = [[panel(u, float(v)) + Vector((math.sin(angle), -math.cos(angle), 0)) * .005
                      for v in np.linspace(.15, .83, 5)] for u in (.18, .42, .68, .88)]
            parts.append(cords(prefix + f'KusazuriLacing_{sector}_{tier}', paths, lace, fit, weights))
    return parts


def japanese_helmet(fit, plate, binding):
    prefix = 'Helmet_Japanese_Leather_01_'
    head, rx, ry, cy, brow, height, _, _ = head_forms(fit)
    # Both scalp and separate forehead mesh are measured by the shared head helper.
    def dome(u, v):
        angle = math.tau * u
        phi = (.995 - v * .99) * math.pi / 2
        return Vector((head.x + (rx + .002) * math.sin(phi) * math.sin(angle),
                       cy - (ry + .002) * math.sin(phi) * math.cos(angle),
                       brow + .016 + (height + .014) * math.cos(phi)))
    parts = [surface(prefix + 'Hachi', dome, plate, fit, 'J_Bip_C_Head', rows=14, cols=48)]
    for tier in range(4):
        def shikoro(u, v, tier=tier):
            a = .78 + (math.tau - 1.56) * u
            extension = .010 + .013 * tier + .014 * v
            return Vector((head.x + (rx + extension) * math.sin(a),
                           cy - (ry + extension) * math.cos(a), brow + .015 - .029 * tier - .037 * v))
        parts.append(surface(prefix + f'Shikoro_{tier}', shikoro, plate, fit, 'J_Bip_C_Head', rows=3, cols=40))
    def visor(u, v):
        a = (u - .5) * 1.65
        return Vector((head.x + (rx + .003 + .018 * v) * math.sin(a),
                       cy - (ry + .003 + .032 * v) * math.cos(a), brow + .025 - .007 * v))
    parts.append(surface(prefix + 'Mabisashi', visor, plate, fit, 'J_Bip_C_Head', rows=3, cols=24))
    paths = [[dome(float(u), float(v)) + Vector((math.sin(math.tau * u), -math.cos(math.tau * u), .7)) * .002
              for v in np.linspace(.02, .90, 18)] for u in np.linspace(0, 1, 9)[:-1]]
    parts.append(cords(prefix + 'RibBinding', paths, binding, fit, lambda p: {'J_Bip_C_Head': 1}, radius=.002))
    fit.arm['cultural_helmet_measurement'] = json.dumps({'rx': rx, 'ry': ry, 'brow': brow, 'top': brow + height})
    return parts


def footwear(fit, plate, leather, cloth, sole, binding):
    parts = []
    for culture in ('Japanese', 'Cloth_Western'):
        prefix = 'Boots_Japanese_Leather_01_' if culture == 'Japanese' else 'Boots_Cloth_Western_01_'
        for side, sign in (('L', 1), ('R', -1)):
            foot = fit.bone('J_Bip_' + side + '_Foot')
            top = foot.z + (.063 if culture == 'Japanese' else .010)
            rings, footprint, low = last(fit, side, sign, top)
            mat = leather if culture == 'Japanese' else cloth
            parts.append(tag(shoe_mesh(prefix + 'Upper_' + side, rings, mat, fit, side, thickness=.002)))
            sole_rows = [[Vector((p.x, p.y, z)) for p in footprint] for z in (low - .006, low + .003)]
            parts.append(tag(shoe_mesh(prefix + 'Sole_' + side, sole_rows, sole, fit, side, cap=True)))
            cuff = [[p + Vector((0, 0, z)) for p in rings[-1]] for z in (-.005, .002)]
            parts.append(tag(shoe_mesh(prefix + 'Welt_' + side, cuff, binding, fit, side, thickness=.002)))
            paths = [[p + Vector((0, 0, .002)) for p in rings[3] + [rings[3][0]]]]
            parts.append(cords(prefix + 'Stitch_' + side, paths, binding, fit, fit.weights, radius=.0008))
            if culture == 'Japanese':
                lower, ankle = 'J_Bip_' + side + '_LowerLeg', 'J_Bip_' + side + '_Foot'
                for splint in range(3):
                    fn = limb_surface(fit, lower, ankle, .16, .78, .015, angular=math.pi)
                    def shin(u, v, splint=splint, fn=fn):
                        return fn(.25 + splint * .17 + u * .15, v)
                    parts.append(surface(prefix + f'Suneate_{splint}_{side}', shin, plate, fit, lower, rows=12, cols=5))
                for tier in range(2):
                    fn = limb_surface(fit, lower, ankle, .23 + .43 * tier, .26 + .43 * tier, .020)
                    parts.append(surface(prefix + f'ShinTie_{tier}_{side}', fn, binding, fit, lower, rows=2, cols=40, thickness=.002))
    reweight_boots(fit, parts)
    return parts


def copy_group(old_prefix, new_prefix, replacement, old_materials=None):
    parts = []
    sources = [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith(old_prefix + '_')]
    assert sources, old_prefix
    for source in sources:
        obj = clone(source, new_prefix + source.name[len(old_prefix):])
        for index, mat in enumerate(obj.data.materials):
            if mat and (mat in old_materials if old_materials is not None else 'Iron' in mat.name):
                obj.data.materials[index] = replacement
        parts.append(obj)
    return parts


def fit_skirt_clearance(fit, parts):
    """Fit the new skirt to the measured hip/thigh envelope, including inner pants."""
    assert not fit.arm.get('cultural_skirt_clearance'), 'Clearance already applied'
    top, bottom = fit.hip + .067, fit.knee + (fit.hip - fit.knee) * .30
    pants = bpy.data.objects['Armor_Japanese_Leather_01_UnderPants']
    points = np.array([list(p) for p in fit.points] + [list(pants.matrix_world @ v.co) for v in pants.data.vertices])
    levels = np.linspace(bottom - .012, top + .012, 40)
    angles = np.linspace(0, math.tau, 97)
    directions = np.column_stack((np.sin(angles), -np.cos(angles)))
    profiles = []
    for z in levels:
        section = points[np.abs(points[:, 2] - z) < .026, :2]
        assert len(section), ('Empty skirt section', z)
        profiles.append((section @ directions.T).max(axis=0) + .014)
    profiles = np.array(profiles)
    changed, largest = 0, 0
    for obj in parts:
        if not obj.name.startswith('Armor_Japanese_') or 'Kusazuri' not in obj.name:
            continue
        inverse = obj.matrix_world.inverted()
        for vertex in obj.data.vertices:
            p = obj.matrix_world @ vertex.co
            angle = math.atan2(p.x, -p.y) % math.tau
            direction = Vector((math.sin(angle), -math.cos(angle), 0))
            target = float(np.interp(p.z, levels, [np.interp(angle, angles, row) for row in profiles]))
            canonical = fit.torso(angle, fit.hip + .033, .021)
            canonical += direction * (.020 * (top - p.z) / (top - bottom))
            delta = max(0, target - canonical.dot(direction))
            vertex.co = inverse @ (p + direction * delta)
            largest = max(largest, delta)
            changed += delta > 0
        obj.data.update()
    fit.arm['cultural_skirt_clearance'] = True
    report = {'sex': fit.sex, 'changed_vertices': changed, 'max_offset_m': largest,
              'basis': 'Actual body and new inner pants at each hip/thigh height; originals untouched.'}
    (QA / f'{fit.sex}_skirt_clearance.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('SKIRT_CLEARANCE', report, flush=True)


def build(fit):
    assert REFERENCE.is_file(), REFERENCE
    assert not any(o.type == 'MESH' and o.name.startswith(tuple(p + '_' for p in PREFIXES)) for o in bpy.data.objects)
    plate = material('Leather', (.22, .10, .045), rough=.76)
    leather = material('SoftLeather', (.09, .049, .026), rough=.81)
    cloth = material('ClothWestern', (.23, .26, .29), rough=.95, weave=True)
    padding = material('Padding', (.10, .12, .14), rough=.93, weave=True)
    binding = material('Cord', (.24, .22, .17), rough=.88, weave=True)
    sole = material('TextileSole', (.11, .10, .075), rough=.96, weave=True)
    iron = material('DarkIron', (.13, .15, .17), metal=.82, rough=.65)
    steel = material('RefinedSteel', (.48, .55, .61), metal=.96, rough=.26)
    parts = japanese_armor(fit, plate, padding, binding)
    parts += japanese_helmet(fit, plate, leather)
    parts += footwear(fit, plate, leather, cloth, sole, binding)
    for slot in ('Armor', 'Helmet', 'Boots'):
        for grade, mat in (('Iron', iron), ('Steel', steel)):
            parts += copy_group(f'{slot}_Japanese_Leather_01', f'{slot}_Japanese_{grade}_01', mat, {plate})
    for old, new in (('Armor_Iron_01', 'Armor_Chinese_Steel_01'),
                     ('Boots_Iron_01', 'Boots_Chinese_Steel_01'),
                     ('Armor_Western_Iron_01', 'Armor_Western_Steel_01'),
                     ('Helmet_Western_Iron_01', 'Helmet_Western_Steel_01'),
                     ('Boots_Western_Iron_01', 'Boots_Western_Steel_01')):
        parts += copy_group(old, new, steel)
    if fit.sex == 'female':
        fit_skirt_clearance(fit, parts)
    reference_hash = hashlib.sha256(REFERENCE.read_bytes()).hexdigest()
    for obj in parts:
        obj['cultural_reference_sha256'] = reference_hash
    return parts


def save(fit, parts):
    # Save only new assets, native rig, and a small body/face fitting context.
    scene = bpy.data.scenes.new('CulturalArmorSource')
    for obj in [fit.arm, fit.body, *parts, *[o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith('Face_Standard_01')]]:
        scene.collection.objects.link(obj)
    bpy.data.libraries.write(str(WORK / f'cultural_armor_{fit.sex}.blend'), {scene}, path_remap='RELATIVE_ALL', compress=True)
    bpy.data.scenes.remove(scene)


def export(fit, parts):
    reset_rig(fit.arm)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [fit.arm, *parts]:
        obj.hide_viewport = obj.hide_render = False
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = fit.arm
    bpy.ops.export_scene.gltf(filepath=str(WORK / f'subset_armor_{fit.sex}.glb'), export_format='GLB',
                              use_selection=True, export_animations=False, export_skins=True,
                              export_morph=False, export_apply=False)
    report = {'sex': fit.sex, 'reference': str(REFERENCE.relative_to(ROOT)),
              'groups': {p.lower(): {'prefix': p, 'meshes': sorted(o.name for o in parts if o.name.startswith(p + '_'))} for p in PREFIXES}}
    (QA / f'{fit.sex}_manifest.json').write_text(json.dumps(report, indent=2), encoding='utf-8')


def preview(fit, parts):
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'MATERIAL'
    scene.display.shading.show_cavity = True
    scene.display.shading.show_shadows = True
    scene.display.shading.background_type = 'WORLD'
    if scene.world is None:
        scene.world = bpy.data.worlds.new('CulturalArmorStudio')
    scene.world.color = (.12, .12, .12)
    scene.render.resolution_x = scene.render.resolution_y = 1200
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    data = bpy.data.cameras.new('CulturalArmorReview')
    camera = bpy.data.objects.new('CulturalArmorReview', data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    data.type = 'ORTHO'
    destination = QA / ('draft_revision_2' if fit.arm.get('cultural_skirt_clearance') else 'draft')
    destination.mkdir(exist_ok=True)
    body_top = max(p.z for p in fit.points)
    def capture(label, target, scale, angle):
        data.ortho_scale = scale
        a = math.radians(angle)
        camera.location = target + Vector((5 * math.sin(a), -5 * math.cos(a), 0))
        camera.rotation_euler = (target - camera.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = str(destination / f'{fit.sex}_{label}.png')
        bpy.ops.render.render(write_still=True)
    for style in ('Japanese_Leather', 'Japanese_Iron', 'Japanese_Steel', 'Chinese_Steel', 'Western_Steel', 'Cloth_Western'):
        reset_rig(fit.arm)
        selected = [o for o in parts if style in o.name]
        for obj in scene.objects:
            if obj.type == 'MESH':
                obj.hide_render = not (obj in selected or obj == fit.body or obj.name.startswith('Face_Standard_01'))
        for label, angle in (('front', 0), ('back', 180), ('side', 90), ('threequarter', 35)):
            if style == 'Cloth_Western':
                capture(style + '_' + label, Vector((0, -.025, .13)), .55, angle)
            else:
                capture(style + '_' + label, Vector((0, 0, body_top * .51)), body_top * 1.20, angle)
        if style != 'Cloth_Western':
            # Extremal frames are measured from the original action, not guessed by time.
            for clip in ('walk', 'run', 'attack_axe'):
                action = bpy.data.actions.get(clip)
                if action is None:
                    continue
                fit.arm.animation_data_create()
                fit.arm.animation_data.action = action
                samples = []
                for frame in range(int(action.frame_range[0]), int(action.frame_range[1]) + 1):
                    scene.frame_set(frame)
                    samples.append((max(abs(fit.arm.pose.bones['J_Bip_' + s + '_LowerLeg'].matrix_basis.to_quaternion().angle) for s in ('L', 'R')), frame))
                extreme = max(samples)[1]
                scene.frame_set(extreme)
                capture(style + f'_{clip}_peak_{extreme}', Vector((0, 0, body_top * .50)), body_top * 1.28, 35)
    reset_rig(fit.arm)
    bpy.data.objects.remove(camera, do_unlink=True)


def component(obj):
    return next(p for p in PREFIXES if obj.name.startswith(p + '_'))


def validate_parts(fit, parts):
    counts = {p: 0 for p in PREFIXES}
    for obj in parts:
        prefix = component(obj)
        counts[prefix] += 1
        assert obj.parent == fit.arm, obj.name
        assert obj['worldgoing_visual_id'] == prefix.lower(), obj.name
        assert obj['worldgoing_component_slot'] == prefix.split('_')[0].lower(), obj.name
        assert obj.data.uv_layers and obj.data.polygons and obj.data.vertices, obj.name
        assert all(m.object == fit.arm for m in obj.modifiers if m.type == 'ARMATURE'), obj.name
        for vertex in obj.data.vertices:
            weights = [g.weight for g in vertex.groups]
            assert weights and abs(sum(weights) - 1) < 1e-5, (obj.name, vertex.index, weights)
            assert all(obj.vertex_groups[g.group].name in fit.arm.data.bones for g in vertex.groups), obj.name
        uv = np.array([tuple(d.uv) for d in obj.data.uv_layers.active.data])
        assert np.isfinite(uv).all() and np.ptp(uv, axis=0).min() > 1e-7, obj.name
    assert all(counts.values()), counts
    return counts


def test(fit):
    from load_authored_cultural_armor import load_cultural_armor
    sys.path.insert(0, str(ROOT / 'scripts/tests'))
    from validate_chinese_cloak_assets import read_glb, accessor
    old = {o.name: (o.as_pointer(), o.data.as_pointer() if o.data else None) for o in bpy.data.objects}
    actions = {a.name: a.as_pointer() for a in bpy.data.actions}
    bones = [(b.name, list(map(list, b.matrix_local))) for b in fit.arm.data.bones]
    parts = [o for group in load_cultural_armor(fit.arm, fit.sex == 'female') for o in group]
    counts = validate_parts(fit, parts)
    assert old == {name: (bpy.data.objects[name].as_pointer(), bpy.data.objects[name].data.as_pointer()
                         if bpy.data.objects[name].data else None) for name in old}
    assert actions == {a.name: a.as_pointer() for a in bpy.data.actions}
    assert bones == [(b.name, list(map(list, b.matrix_local))) for b in fit.arm.data.bones]
    doc, raw = read_glb(WORK / f'subset_armor_{fit.sex}.glb')
    original, original_raw = read_glb(BASE / f'standard_anime_{fit.sex}_character_pack.glb')
    assert not doc.get('animations'), 'Subset must not carry animation overrides'
    new_names = {n['name'] for n in doc['nodes'] if 'mesh' in n}
    assert new_names == {o.name for o in parts}, (len(new_names), len(parts))
    skin_checks = 0
    for skin in doc['skins']:
        names = [doc['nodes'][i]['name'] for i in skin['joints']]
        compatible = [s for s in original['skins'] if [original['nodes'][i]['name'] for i in s['joints']] == names]
        assert compatible, 'Original skeleton joint ordering changed'
        assert any(np.allclose(accessor(doc, raw, skin['inverseBindMatrices']),
                              accessor(original, original_raw, s['inverseBindMatrices']), atol=1e-6)
                   for s in compatible), 'Original bind matrices changed'
        skin_checks += 1
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            attributes = primitive['attributes']
            for key in ('POSITION', 'NORMAL', 'TEXCOORD_0', 'JOINTS_0', 'WEIGHTS_0'):
                assert key in attributes, (mesh['name'], key)
                assert np.isfinite(accessor(doc, raw, attributes[key])).all(), (mesh['name'], key)
            weights = accessor(doc, raw, attributes['WEIGHTS_0'])
            assert np.allclose(weights.sum(axis=1), 1, atol=1e-5), mesh['name']
    for prefix in PREFIXES:
        matching = [o for o in parts if o.name.startswith(prefix + '_')]
        metallic = [m.node_tree.nodes.get('Principled BSDF').inputs['Metallic'].default_value
                    for o in matching for m in o.data.materials if m and m.use_nodes]
        if '_Steel_' in prefix:
            assert max(metallic) >= .9, prefix
        if prefix == 'Boots_Cloth_Western_01':
            assert max(metallic) == 0, prefix
            uppers = [o for o in matching if '_Upper_' in o.name]
            assert len(uppers) == 2 and all('Cloth' in o.data.materials[0].name for o in uppers)
    report = {'sex': fit.sex, 'groups': counts, 'mesh_count': len(parts), 'skin_checks': skin_checks,
              'old_objects_unchanged': len(old), 'old_actions_unchanged': len(actions),
              'result': 'PASS', 'scope': 'Additive loader, UV/PBR/native weights and subset skeleton; visual/gameplay acceptance separate.'}
    (QA / f'{fit.sex}_tests.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('CULTURAL_ARMOR_TEST_PASS', fit.sex, len(parts), flush=True)


def bounds(obj):
    points = [obj.matrix_world @ v.co for v in obj.data.vertices]
    return [np.min(points, axis=0).tolist(), np.max(points, axis=0).tolist()]


def inspect(fit):
    report = {
        'sex': fit.sex,
        'body': bounds(fit.body),
        'bones': {b.name: list(fit.bone(b.name)) for b in fit.arm.data.bones
                  if b.name.startswith('J_Bip_') and not any(s in b.name for s in ('Thumb', 'Index', 'Middle', 'Ring', 'Little'))},
        'profiles': list(zip(fit.levels.tolist(), fit.profiles.tolist())),
        'sources': {o.name: {'bounds': bounds(o), 'vertices': len(o.data.vertices),
                              'materials': [m.name if m else None for m in o.data.materials]}
                    for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith(
                        ('Armor_Iron_', 'Armor_Western_Iron_', 'Helmet_Western_Iron_',
                         'Boots_Iron_', 'Boots_Western_Iron_', 'Boots_Medieval_',
                         'Face_Standard_01', 'Armor_Light_Leather_01_Pants'))},
    }
    (QA / f'{fit.sex}_measurements.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('MEASUREMENTS', fit.sex, report['body'], len(report['sources']), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sex', choices=('male', 'female'), required=True)
    parser.add_argument('--stage', choices=('inspect', 'test', 'build', 'export', 'preview', 'fit-skirt'), required=True)
    parser.add_argument('--gpu-granted', action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    QA.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    source = BASE / f'standard_anime_{args.sex}_character_pack.blend' if args.stage in ('inspect', 'test', 'build') else WORK / f'cultural_armor_{args.sex}.blend'
    bpy.ops.wm.open_mainfile(filepath=str(source))
    arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    reset_rig(arm)
    fit = Fitting(arm, args.sex)
    if args.stage == 'inspect':
        inspect(fit)
    elif args.stage == 'test':
        test(fit)
    else:
        parts = build(fit) if args.stage == 'build' else [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith(tuple(p + '_' for p in PREFIXES))]
        counts = validate_parts(fit, parts)
        if args.stage == 'fit-skirt':
            fit_skirt_clearance(fit, parts)
        if args.stage in ('build', 'fit-skirt'):
            save(fit, parts)
        if args.stage in ('build', 'export', 'fit-skirt'):
            export(fit, parts)
        if args.stage == 'preview':
            assert args.gpu_granted, 'Coordinate GPU slot with main before rendering'
            preview(fit, parts)
        print('GROUPS', counts, flush=True)
    print('CULTURAL_ARMOR_STAGE_PASS', args.sex, args.stage, flush=True)


if __name__ == '__main__':
    main()
