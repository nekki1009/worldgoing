"""Read-only measurement of each current neutral face's actual material regions."""
import json
from pathlib import Path
import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/neutral_faces_20260918'
for sex in ('male', 'female'):
    bpy.ops.wm.open_mainfile(filepath=str(OUT / f'baseline/standard_anime_{sex}_character_pack.blend'))
    face = bpy.data.objects['Face_Standard_01']
    points = np.array([tuple(face.matrix_world @ v.co) for v in face.data.vertices])
    report = {'sex': sex, 'object': face.name, 'vertices': len(points), 'matrix': [list(row) for row in face.matrix_world],
              'shape_keys': list(face.data.shape_keys.key_blocks.keys()) if face.data.shape_keys else [], 'regions': []}
    for index, mat in enumerate(face.data.materials):
        indices = sorted({v for p in face.data.polygons if p.material_index == index for v in p.vertices})
        if not indices: continue
        region = points[indices]
        entry = {'material': mat.name, 'index': index, 'vertices': len(indices), 'min': region.min(0).tolist(), 'max': region.max(0).tolist()}
        for sign in (-1, 1):
            half = region[region[:, 0]*sign > .001]
            if len(half): entry[str(sign)] = {'min': half.min(0).tolist(), 'max': half.max(0).tolist(), 'mean': half.mean(0).tolist()}
        report['regions'].append(entry)
    (OUT / f'{sex}_face_measurements.json').write_text(json.dumps(report, indent=2))
    print('NEUTRAL_FACE_MEASUREMENTS', json.dumps(report), flush=True)
