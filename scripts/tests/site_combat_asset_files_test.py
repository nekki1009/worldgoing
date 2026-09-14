"""Prove that the additive export did not re-author the reviewed character."""
import json
import struct
import hashlib
import sys
from pathlib import Path
from weapon_refresh_files_test import check as check_weapon_refresh

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / '.godot-temp/site_combat_assets'
NEW = {'guard_raise', 'guard_lower', 'guard_break', 'unconscious', 'get_up',
       'rescue', 'reload_bow', 'reload_crossbow'}
NEW |= {prefix + suffix for prefix in ['guard_weapon', 'guard_polearm'] for suffix in ['', '_raise', '_lower', '_break']}
FORMAL = ROOT / 'assets/characters/human/q35'
LOW_POSE = ROOT / '.godot-temp/mingguang_low_pose_20260912'
SKIRT_PARTS = {'Armor_Mingguang_01_' + name for name in ['PleatedSkirt',
    'Pteruges_Front', 'Pteruges_Silver', 'Pteruges_Studs', 'Skirt_Rear',
    'Skirt_Rear_Rim', 'Skirt_Side_L', 'Skirt_Rim_L', 'Skirt_Side_R', 'Skirt_Rim_R']}
LOW_CLIPS = {'down', 'unconscious', 'get_up', 'rescue'}


def glb(path):
    raw = path.read_bytes()
    assert raw[:4] == b'glTF' and struct.unpack_from('<I', raw, 8)[0] == len(raw)
    size = struct.unpack_from('<I', raw, 12)[0]
    return json.loads(raw[20:20+size]), raw[28+size:]


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').digest()


def preserved(before, after, sex, allow_skirt):
    for key in ['nodes', 'skins', 'materials', 'textures', 'images', 'scenes', 'samplers']:
        assert before.get(key) == after.get(key), (sex, key)
    changed = {node['mesh'] for node in before['nodes'] if node.get('name') in SKIRT_PARTS} if allow_skirt else set()
    assert len(before['meshes']) == len(after['meshes'])
    for index, mesh in enumerate(before['meshes']):
        if index not in changed:
            assert mesh == after['meshes'][index], (sex, 'unrelated mesh', index)
    for key in ['accessors', 'bufferViews']:
        assert before[key] == after[key][:len(before[key])], (sex, key)
    for original, current in zip(before['animations'], after['animations']):
        assert {k: v for k, v in original.items() if k not in ['channels', 'samplers']} == {k: v for k, v in current.items() if k not in ['channels', 'samplers']}
        for key in ['channels', 'samplers']:
            assert original[key] == current[key][:len(original[key])], (sex, original['name'], key)
        extra = current['channels'][len(original['channels']):]
        if extra:
            assert allow_skirt and original['name'] in LOW_CLIPS
            assert len(extra) == 10
            assert {after['nodes'][c['target']['node']]['name'] for c in extra} == SKIRT_PARTS
            assert all(c['target']['path'] == 'weights' for c in extra)


for sex in ['male', 'female']:
    stem = f'standard_anime_{sex}_character_pack'
    before, old_binary = glb(WORK / 'baseline' / (stem + '.glb'))
    allow_skirt = (LOW_POSE / 'candidate' / (sex + '.glb')).exists()
    candidate = (LOW_POSE if allow_skirt else WORK) / 'candidate'
    after, binary = glb(candidate / (sex + '.glb'))
    if '--candidate' not in sys.argv:
        refreshed = json.loads((FORMAL / (stem + '.json')).read_text(encoding='utf-8')).get('weapon_refresh', {}).get('stage') == 'final'
        comparison = ROOT / '.godot-temp/weapon_refresh_20260913/baseline' if refreshed else FORMAL
        for extension in ['blend', 'glb', 'json']:
            name = sex if refreshed else stem
            assert sha(comparison / (name + '.' + extension)) == sha(candidate / (sex + '.' + extension)), f'Baseline {sex}.{extension} differs from verified candidate'
        if refreshed:
            check_weapon_refresh(sex, formal=True)
    assert binary[:len(old_binary)] == old_binary, f'{sex}: original binary changed'
    preserved(before, after, sex, allow_skirt)
    if allow_skirt:
        baseline = LOW_POSE / 'grounded_baseline'
        if not baseline.exists():
            baseline = LOW_POSE / 'baseline'
        prior, prior_binary = glb(baseline / (sex + '.glb'))
        assert binary[:len(prior_binary)] == prior_binary
        preserved(prior, after, sex, True)
        print('MINGGUANG_SCOPED_PRESERVATION_PASS', sex, '10 skirt meshes; 4 morph tracks; all prior skeleton channels unchanged')
    names = {clip['name'] for clip in after['animations']} - {clip['name'] for clip in before['animations']}
    assert names == NEW, (sex, names)
    for clip in after['animations'][len(before['animations']):]:
        duration = max(after['accessors'][sampler['input']]['max'][0] for sampler in clip['samplers'])
        assert duration > 0 and all(channel['target']['path'] in ['translation', 'rotation', 'scale'] or
            (allow_skirt and clip['name'] in LOW_CLIPS and channel['target']['path'] == 'weights' and
             after['nodes'][channel['target']['node']]['name'] in SKIRT_PARTS) for channel in clip['channels'])
    print('SITE_COMBAT_FILE_PRESERVATION_PASS', sex, len(before['nodes']), 'nodes;',
          len(before['meshes']), 'meshes;', len(old_binary), 'original bytes;', sorted(names))

props, _ = glb(WORK / 'candidate/combat_props.glb')
for extension in ['blend', 'glb']:
    assert sha(FORMAL / 'combat' / ('combat_props.' + extension)) == sha(WORK / 'candidate' / ('combat_props.' + extension)), 'Formal combat props differ from candidate'
assert {'Arrow', 'Bolt', 'QuiverArrow', 'QuiverBolt'} <= {node['name'] for node in props['nodes']}
assert not props.get('skins') and not props.get('animations'), 'Props must not introduce another rig'
print('SITE_COMBAT_PROPS_FILE_PASS')
