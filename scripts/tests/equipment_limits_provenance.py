"""Snapshot exact pre-fix atlas provenance; no assets are published by snapshot."""
import hashlib
import copy
import json
import os
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/equipment_limits_20260919'


def md5(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'md5').hexdigest()


def resource_path(resource):
    assert resource.startswith('res://')
    path = (ROOT / resource[6:]).resolve()
    assert path.is_relative_to(ROOT)
    return path


def snapshot():
    target = OUT / 'atlas_snapshot.json'
    assert not target.exists(), 'Never replace original baseline'
    previous = ROOT / 'output/equipment_matrix_20260918'
    resources = json.loads((previous / 'atlas_snapshot.json').read_text())['active']
    resources.update(json.loads((previous / 'atlas_wagon_snapshot.json').read_text())['active'])
    active, sources = {}, {}
    for resource in resources:
        path = resource_path(resource)
        value = json.loads(path.read_text(encoding='utf-8-sig'))
        for source, expected in value['source_fingerprints'].items():
            original = resource_path(source)
            if source == 'res://scripts/ui/human_character_3d_editor.gd':
                original = OUT / 'scabbard/editor_before.gd.txt'
            if source not in sources:
                assert md5(original) == expected, ('Not valid at task baseline', resource, source)
            assert sources.get(source, expected) == expected
            sources[source] = expected
            backup = OUT / 'baseline' / source[6:]
            backup.parent.mkdir(parents=True, exist_ok=True)
            if not backup.exists():
                shutil.copy2(original, backup)
        if value.get('source_manifest'):
            assert md5(resource_path(value['source_manifest'])) == value['source_manifest_md5']
        backup = OUT / 'atlas_before' / resource[6:]
        backup.parent.mkdir(parents=True, exist_ok=True)
        if backup.exists():
            assert md5(backup) == md5(path), 'Partial snapshot must match unchanged originals'
        else:
            shutil.copy2(path, backup)
        active[resource] = md5(path)
    target.write_text(json.dumps({'active': active, 'sources': sources}, indent=2), encoding='utf-8')
    print('EQUIPMENT_LIMITS_BASELINE', len(active), 'validated manifests')


def revalidate(publish=False):
    before = json.loads((OUT / 'atlas_snapshot.json').read_text())
    editor = 'res://scripts/ui/human_character_3d_editor.gd'
    dye_baker = 'res://scripts/tools/bake_terrain_army_dyes.gd'
    dye_reader = 'res://scripts/terrain_lab/terrain_army_dye_atlas.gd'
    equipment_reader = 'res://scripts/terrain_lab/terrain_army_equipment_atlas.gd'
    allowed = {editor, dye_baker, dye_reader, equipment_reader}
    current = {path: md5(resource_path(path)) for path in before['sources']}
    assert all(path in allowed or digest == current[path] for path, digest in before['sources'].items())
    def old_text(path):
        return (OUT / 'baseline' / path[6:]).read_text(encoding='utf-8-sig')
    def new_text(path):
        return resource_path(path).read_text(encoding='utf-8-sig')
    # The new sheath branch must be mounted-only; every old foot path is exact.
    new_editor = new_text(editor)
    start = new_editor.index('func _update_scabbard_pose()')
    branch = new_editor.index('\tif _is_mounted:\n', start)
    end = new_editor.index('\telif _selected_animation == &"get_up":', branch)
    restored = new_editor[:branch] + '\tif _selected_animation == &"get_up":' + new_editor[end + len('\telif _selected_animation == &"get_up":'):]
    assert restored == old_text(editor), 'Unrelated editor/foot source change'
    assert new_text(dye_baker) == old_text(dye_baker).replace('func _pack_mask(', 'static func _pack_mask(')
    old_dye, new_dye = old_text(dye_reader), new_text(dye_reader)
    prefix = 'static func apply(sprite: Sprite2D, appearance: Dictionary) -> bool:\n'
    assert old_dye.split(prefix)[0] == new_dye.split(prefix)[0], 'Original shader/policy/reader changed'
    body = new_dye.split('static func apply_record(sprite: Sprite2D, appearance: Dictionary, record: Dictionary) -> bool:\n')[1]
    body = body.replace('\t# All admitted full recipes share this same bounded mask/material cache.\n', '')
    body = body.replace('\tif record.is_empty(): return false\n', '\tvar record := entry(appearance)\n\tif record.is_empty(): return false\n')
    body = body.replace('\tvar key := str(record.mask_path)\n', '\tvar key := _key(appearance)\n')
    assert body == old_dye.split(prefix)[1], 'Changed dye application beyond sharing the same bounded cache'
    def functions(text):
        return dict(re.findall(r'(?:^|\n)static func (\w+)(\([^\n]*\n[\s\S]*?)(?=\nstatic func |\Z)', text))
    old_functions, new_functions = functions(old_text(equipment_reader)), functions(new_text(equipment_reader))
    integrated = {'refresh_female_sources', 'supports', 'frame', '_single_page_recipe', 'dye_entry', 'apply_dye'}
    for name, code in old_functions.items():
        if name not in integrated:
            assert new_functions[name].strip() == code.strip(), 'Changed legacy recipe/packing/query: ' + name
    assert new_functions['_single_page_recipe'].replace(', "guard_weapon", "guard_polearm"', '').strip() == old_functions['_single_page_recipe'].strip()
    pairs = 0
    for section, count in [('regression', 153), ('regression_wagon', 72)]:
        for sex in ('male', 'female'):
            old = json.loads((OUT / section / 'before_fixed' / sex / 'result.json').read_text())
            new = json.loads((OUT / section / 'after_fixed' / sex / 'result.json').read_text())
            assert old['samples'] == new['samples'] and len(new['samples']) == count, (section, sex)
            assert old['editor_md5'] == before['sources'][editor] and new['editor_md5'] == current[editor]
            model = f'res://assets/characters/human/q35/standard_anime_{sex}_character_pack.glb'
            assert old['glb_md5'] == new['glb_md5'] == current[model]
            pairs += count
    # Historical armed rider pixels change intentionally with the corrected
    # sheath. It is not the current fixed-cloth rider owner: leave it stale.
    excluded = 'res://assets/vehicles/logistics/v1/riders/manifest.json'
    pending = {path: digest for path, digest in before['active'].items() if path != excluded}
    encoded, hashes = {}, {}
    while pending:
        progressed = False
        for path, digest in list(pending.items()):
            original = json.loads((OUT / 'atlas_before' / path[6:]).read_text(encoding='utf-8-sig'))
            parent = original.get('source_manifest')
            if not parent and 'source_manifest_md5' in original:
                assert path.endswith('/standard_soldier/recipes/v1/catalog.json')
                parent = 'res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json'
            if parent in pending: continue
            updated = copy.deepcopy(original)
            updated['source_fingerprints'] = {source: current[source] for source in original['source_fingerprints']}
            if parent: updated['source_manifest_md5'] = hashes.get(parent) or md5(resource_path(parent))
            updated['equipment_limits_revalidation'] = {'rebaked': False, 'rgba_pairs': pairs,
                'evidence': OUT.relative_to(ROOT).as_posix(), 'old_manifest_md5': digest}
            content = (json.dumps(updated, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
            encoded[path] = content
            hashes[path] = hashlib.md5(content).hexdigest()
            del pending[path]
            progressed = True
        assert progressed
    assert len(encoded) == 260
    if publish:
        previous_path = OUT / 'atlas_revalidation.json'
        previous = json.loads(previous_path.read_text()) if previous_path.exists() else None
        expected = previous['published_md5'] if previous else before['active']
        assert all(md5(resource_path(path)) == expected[path] for path in encoded), 'Concurrent atlas change'
        assert all(md5(resource_path(path)) == digest for path, digest in current.items()), 'Concurrent source change'
        prior = {path: resource_path(path).read_bytes() for path in encoded}
        if previous:
            history = OUT / ('atlas_revalidation_' + md5(previous_path)[:12] + '.json')
            if not history.exists(): shutil.copy2(previous_path, history)
        replaced = []
        try:
            for path, content in encoded.items():
                target = resource_path(path)
                temp = target.with_suffix('.equipment-limits-incoming')
                assert not temp.exists()
                temp.write_bytes(content)
                os.replace(temp, target)
                replaced.append(path)
        except Exception:
            for path in replaced:
                resource_path(path).write_bytes(prior[path])
            raise
        assert all(md5(resource_path(path)) == digest for path, digest in hashes.items())
    assert md5(resource_path(excluded)) == before['active'][excluded]
    report = {'published': publish, 'manifests': len(encoded), 'rgba_pairs': pairs,
        'published_md5': hashes if publish else {}, 'current_sources': current,
        'excluded_changed_legacy_rider': excluded, 'rebaked': False}
    (OUT / ('atlas_revalidation.json' if publish else 'atlas_preflight.json')).write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('EQUIPMENT_LIMITS_PROVENANCE_PASS', len(encoded), pairs, 'published=', publish)


if __name__ == '__main__':
    if sys.argv[1:] == ['--snapshot']:
        snapshot()
    else:
        assert sys.argv[1:] in [['--revalidate'], ['--revalidate', '--publish']]
        revalidate('--publish' in sys.argv)
