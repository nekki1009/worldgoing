"""Repair UV-only import faults, keeping an immutable backup and exact-diff check."""
import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / '.godot-temp/morph_uv_repair/baseline'
sys.path.insert(0, str(ROOT/'scripts/tools/blender'))
from ensure_morph_uv import patch_glb, projected_uv
from validate_chinese_cloak_assets import read_glb, accessor
import numpy as np


def mesh_without_added_uv(old, new, doc, binary):
    """Allow only the verified UV addition when chaining earlier asset contracts."""
    import copy
    stripped = copy.deepcopy(new)
    assert len(old['primitives']) == len(new['primitives'])
    for p, q in zip(old['primitives'], stripped['primitives']):
        if 'TEXCOORD_0' in p['attributes'] or 'TEXCOORD_0' not in q['attributes']:
            continue
        assert p.get('targets') and 'Texture"' not in json.dumps(doc['materials'][q['material']])
        uv = accessor(doc, binary, q['attributes'].pop('TEXCOORD_0'))
        expected = projected_uv(accessor(doc, binary, q['attributes']['POSITION']))
        assert uv.shape == expected.shape and np.allclose(uv, expected, atol=2e-7, rtol=0)
    return stripped


def validate(before, after):
    import copy
    doc, binary = read_glb(before)
    new, new_binary = read_glb(after)
    stripped = copy.deepcopy(new)
    count = 0
    for mi, mesh in enumerate(doc['meshes']):
        for pi, primitive in enumerate(mesh['primitives']):
            changed = stripped['meshes'][mi]['primitives'][pi]
            if 'TEXCOORD_0' in primitive['attributes']:
                continue
            if 'TEXCOORD_0' not in changed['attributes']:
                assert not primitive.get('targets'), mesh['name']
                continue
            assert primitive.get('targets') and 'Texture"' not in json.dumps(doc['materials'][primitive['material']])
            index = changed['attributes'].pop('TEXCOORD_0')
            uv = accessor(new, new_binary, index)
            assert uv.shape == (doc['accessors'][primitive['attributes']['POSITION']]['count'], 2)
            assert np.isfinite(uv).all() and np.ptp(uv, axis=0).min() > 0
            count += 1
    stripped['accessors'] = stripped['accessors'][:len(doc['accessors'])]
    stripped['bufferViews'] = stripped['bufferViews'][:len(doc['bufferViews'])]
    stripped['buffers'] = doc['buffers']
    assert doc == stripped and new_binary[:len(binary)] == binary, after
    assert not patch_glb(after), 'UV repair must be idempotent'
    return count


def main():
    report = []
    for path in sorted((ROOT/'assets').rglob('*.glb')):
        rel = path.relative_to(ROOT)
        before = BASE/rel
        doc, _ = read_glb(path)
        missing = any(p.get('targets') and 'TEXCOORD_0' not in p['attributes']
                      for mesh in doc['meshes'] for p in mesh['primitives'])
        if not missing and not before.exists():
            continue
        if missing:
            assert '--apply' in sys.argv, ('Unrepaired UVs', rel)
            assert not before.exists(), ('Backup already exists; inspect before retry', before)
            before.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, before)
            patch_glb(path)
        count = validate(before, path)
        report.append({'file': rel.as_posix(), 'uv_surfaces_added': count,
                       'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    assert report, 'No UV repair evidence'
    (BASE.parent/'glb_report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2), flush=True)
    print('MORPH_UV_ASSET_PRESERVATION_PASS', len(report))


if __name__ == '__main__':
    main()
