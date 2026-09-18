"""Exact neutral-expression and editable-source checks on the existing rig."""
import sys
from pathlib import Path
import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/tools/blender'))
from load_authored_neutral_faces import load_neutral_faces

for sex in ('male','female'):
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/f'output/neutral_faces_20260918/baseline/standard_anime_{sex}_character_pack.blend'))
    arm = bpy.data.objects['Armature']
    original_objects = set(bpy.data.objects)
    original_actions = set(bpy.data.actions)
    source = bpy.data.objects['Face_Standard_01']
    positions = np.array([tuple(v.co) for v in source.data.vertices])
    weights = [[(g.group,g.weight) for g in v.groups] for v in source.data.vertices]
    polygons = [(p.material_index,tuple(p.vertices)) for p in source.data.polygons]
    uv = [[tuple(loop.uv) for loop in layer.data] for layer in source.data.uv_layers]
    protected = set()
    for p in source.data.polygons:
        name = source.data.materials[p.material_index].name.lower()
        if 'brow' in name or 'mouth' in name: protected.update(p.vertices)
    parts = load_neutral_faces(arm,sex=='female')
    assert len(parts) == 4 and set(bpy.data.objects) == original_objects|set(parts)
    assert set(bpy.data.actions) == original_actions
    differences = set()
    for obj in parts:
        assert obj.parent == arm and obj['worldgoing_component_slot'] == 'face'
        assert obj.data.shape_keys is None
        assert obj.matrix_world == source.matrix_world
        assert all(m.object == arm for m in obj.modifiers if m.type == 'ARMATURE')
        assert [g.name for g in obj.vertex_groups] == [g.name for g in source.vertex_groups]
        assert [[(g.group,g.weight) for g in v.groups] for v in obj.data.vertices] == weights
        assert [(p.material_index,tuple(p.vertices)) for p in obj.data.polygons] == polygons
        assert [[tuple(loop.uv) for loop in layer.data] for layer in obj.data.uv_layers] == uv
        current = np.array([tuple(v.co) for v in obj.data.vertices])
        assert np.array_equal(current[list(protected)],positions[list(protected)]), 'Mouth or eyebrow expression changed'
        differences.add(current.tobytes())
    assert len(differences) == 4
    print('NEUTRAL_FACES_BLENDER_PASS',sex,'four eye geometries; exact mouth/brows, UV, weights, topology, rig/actions',flush=True)
