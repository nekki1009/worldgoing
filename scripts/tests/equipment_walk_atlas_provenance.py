"""Read-only production audit for the 2026-09-19 walk/helmet correction.

Writes only this task's atlas evidence. There is deliberately no publish mode,
Godot launcher, source-hash override, reader replacement, or asset mutation.
"""
import argparse
import copy
import hashlib
import json
import re
import struct
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TASK = ROOT / 'output/equipment_walk_fix_20260919'
OUT = TASK / 'atlas'
PREVIOUS = ROOT / 'output/equipment_limits_20260919'
EDITOR = 'res://scripts/ui/human_character_3d_editor.gd'
BASE = 'res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json'
CATALOG = 'res://assets/characters/terrain_lab_army/standard_soldier/recipes/v1/catalog.json'
EXCLUDED = 'res://assets/vehicles/logistics/v1/riders/manifest.json'
MODEL_ROOT = 'res://assets/characters/human/q35/'
CHANGED = {
    'armor': ['armor_iron_01', 'armor_western_iron_01'],
    'boots': ['boots_japanese_iron_01', 'boots_japanese_steel_01',
              'boots_western_iron_01', 'boots_western_steel_01'],
    'helmet': ['helmet_leather_01', 'helmet_western_iron_01', 'helmet_western_steel_01'],
}
ALLOWED = {EDITOR} | {MODEL_ROOT + f'standard_anime_{sex}_character_pack.glb'
                      for sex in ('male', 'female')}
BEFORE_WRAPPER_MD5 = '6d007c4fd60295f2591b750be56f5d4f'
PARENT_SAMPLER_MD5 = '93b04e5a53d8871980088d522a72dca0'


def check(ok, message):
    if not ok:
        raise ValueError(message)


def path(resource):
    check(isinstance(resource, str) and resource.startswith('res://'), 'Expected res:// path')
    relative = resource[6:]
    check('\\' not in relative and '..' not in relative.split('/'), 'Noncanonical resource path')
    target = (ROOT / relative).resolve()
    check(target.is_relative_to(ROOT) and target != ROOT, 'Path escapes project')
    return target


def resource(file):
    return 'res://' + file.relative_to(ROOT).as_posix()


def load(file):
    return json.loads(file.read_text(encoding='utf-8-sig'))


def digest(file, algorithm='md5'):
    with file.open('rb') as stream:
        return hashlib.file_digest(stream, algorithm).hexdigest()


def record(file):
    return {'md5': digest(file), 'sha256': digest(file, 'sha256'), 'bytes': file.stat().st_size}


def create(file, data):
    check(file.resolve().is_relative_to(OUT.resolve()), 'Evidence writes must stay in atlas output')
    file.parent.mkdir(parents=True, exist_ok=True)
    with file.open('xb') as stream:
        stream.write(data)


def write_json(file, data):
    create(file, (json.dumps(data, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))


def preserve(file, target):
    if target.exists():
        check(record(target) == record(file), 'Partial snapshot differs: ' + str(target))
    else:
        create(target, file.read_bytes())


def baseline_source(src):
    if src == EDITOR:
        return TASK / 'baseline/human_character_3d_editor.gd.txt'
    if src in ALLOWED:
        return TASK / 'baseline' / path(src).name
    return path(src)


def parent_of(src, value):
    if 'source_manifest' in value:
        return value['source_manifest']
    if 'source_manifest_md5' in value:
        check(src == CATALOG, 'Unknown implicit parent: ' + src)
        return BASE
    return None


def appearances(value):
    result = value.get('appearances', [])
    if 'appearance' in value:
        result = [value['appearance']]
        # The base atlas really changes weapons/shields per clip; preserve that
        # distinction instead of treating the manifest's default as every pose.
        for clip in value.get('clips', []):
            actual = copy.deepcopy(value['appearance'])
            for slot in ('weapon', 'shield'):
                if slot in clip:
                    actual['parts'][slot] = clip[slot]
            if actual not in result:
                result.append(actual)
    return result


def changed_parts(value):
    return sorted({slot + ':' + actual['parts'][slot]
                   for actual in appearances(value) for slot, ids in CHANGED.items()
                   if actual.get('parts', {}).get(slot) in ids})


def payloads(src, value):
    result = {}
    pages = value.get('pages', [])
    if 'atlas' in value:
        pages = [value['atlas']]
    for page in pages:
        for field, hash_field in [('path', 'png_md5'), ('resource_path', 'resource_md5')]:
            if field not in page:
                continue
            target = page[field]
            info = record(path(target))
            if hash_field in page:
                check(info['md5'] == page[hash_field], 'Page hash mismatch: ' + target)
            if field == 'path':
                with path(target).open('rb') as stream:
                    header = stream.read(24)
                check(header[:8] == b'\x89PNG\r\n\x1a\n', 'Invalid PNG: ' + target)
                check(struct.unpack('>II', header[16:24]) == (page['width'], page['height']),
                      'Page dimensions differ: ' + target)
            result[target] = info
    if 'mask_path' in value:
        target = value['mask_path']
        result[target] = record(path(target))
        check(result[target]['md5'] == value['mask_md5'], 'Dye hash mismatch: ' + target)
    for name, expected in value.get('asset_md5', {}).items():
        check('/' not in name and '\\' not in name and name not in ('.', '..'), 'Unsafe asset basename')
        target = resource(path(src).parent / name)
        result[target] = record(path(target))
        check(result[target]['md5'] == expected, 'Rider payload mismatch: ' + target)
    return result


def snapshot():
    check(not (OUT / 'snapshot.json').exists(), 'Never replace the task baseline')
    proof_path = PREVIOUS / 'atlas_revalidation.json'
    proof = load(proof_path)
    check(proof['published'] is True and proof['manifests'] == len(proof['published_md5']) == 260,
          'Expected the latest 260 published-manifest proof')
    old = load(PREVIOUS / 'atlas_snapshot.json')
    active = proof['published_md5']
    check(set(active) == set(old['active']) - {EXCLUDED}, 'Prior admission set drift')
    sources = proof['current_sources']
    check(len(sources) == 22, 'Review changed source inventory')
    for src, expected in sources.items():
        check(digest(baseline_source(src)) == expected, 'Task-before source mismatch: ' + src)
        if src not in ALLOWED:
            preserve(path(src), OUT / 'source_before' / src[6:])
    manifests, files = {}, {}
    for src, expected in active.items():
        check(digest(path(src)) == expected, 'Formal manifest no longer matches prior proof: ' + src)
        value = load(path(src))
        check(value.get('source_fingerprints'), 'Manifest has no sources: ' + src)
        for dependency, claimed in value['source_fingerprints'].items():
            check(sources.get(dependency) == claimed, 'Non-baseline manifest source: ' + src)
        parent = parent_of(src, value)
        if parent:
            check(parent in active and value['source_manifest_md5'] == active[parent], 'Parent mismatch: ' + src)
        if 'mask_path' in value:
            check(value['complete'] is True, 'Incomplete dye: ' + src)
            parent_value = load(path(parent))
            check(value['appearance'] == parent_value['appearance'] and value['frame_count'] == len(parent_value['frames']),
                  'Dye does not cover exact parent recipe: ' + src)
        preserve(path(src), OUT / 'manifest_before' / src[6:])
        manifest_payloads = payloads(src, value)
        for target, info in manifest_payloads.items():
            check(target not in files or files[target] == info, 'Conflicting payload: ' + target)
            files[target] = info
        manifests[src] = {'file': record(path(src)), 'parent': parent, 'kind': value.get('kind', ''),
                          'recipe_key': value.get('recipe_key'), 'appearances': appearances(value),
                          'changed_parts': changed_parts(value), 'frames': len(value.get('frames', [])),
                          'dye_frames': value.get('frame_count'), 'payloads': list(manifest_payloads)}
    catalog = load(path(CATALOG))
    expected_keys = {f'standard_soldier_v2/m{mask:02d}' for mask in range(32)}
    check(set(catalog['recipes']) == expected_keys, 'Re-review catalog inventory: not the known 32')
    for key, batches in catalog['recipes'].items():
        check(len(batches) == 5 and all(src in active for src in batches), 'Missing recipe pages')
        values = [load(path(src)) for src in batches]
        check(all(v['recipe_key'] == key and v.get('recipe_iron', 0) == 0 for v in values), 'Wrong catalog recipe')
        check(sum(len(v['frames']) for v in values) == 584, 'Incomplete original recipe')
        check([(v['batch']['first'], v['batch']['count']) for v in values] ==
              [(0, 128), (128, 128), (256, 128), (384, 128), (512, 72)], 'Wrong batch coverage')
    check(digest(path(EXCLUDED)) == old['active'][EXCLUDED], 'Excluded historical rider changed')
    excluded = load(path(EXCLUDED))
    mismatches = {src: claimed for src, claimed in excluded['source_fingerprints'].items()
                  if sources.get(src) != claimed}
    check(mismatches, 'Historical armed rider unexpectedly became source-valid')
    preserve(path(EXCLUDED), OUT / 'excluded_before' / EXCLUDED[6:])
    baseline = {}
    for file in sorted((TASK / 'baseline').iterdir()):
        if file.name == 'human_character_3d_editor.gd.txt' or file.name.startswith('standard_anime_'):
            baseline[resource(file)] = record(file)
    check(len(baseline) == 7, 'Expected six formal model backups and editor')
    # Detect writes which raced the snapshot, without trusting a cached digest.
    check(all(digest(path(src)) == expected for src, expected in active.items()), 'Atlas changed during snapshot')
    check(all(digest(baseline_source(src)) == expected for src, expected in sources.items()), 'Source changed during snapshot')
    preserve(proof_path, OUT / 'previous_260_proof.json')
    data = {'schema_version': 1, 'created_utc': datetime.now(timezone.utc).isoformat(),
            'published': False, 'admission': 'Task-before provenance only; no new runtime admission',
            'prior_proof': record(proof_path), 'active': active, 'sources': sources,
            'baseline_files': baseline, 'manifests': manifests, 'payloads': files,
            'excluded': {EXCLUDED: {'file': record(path(EXCLUDED)), 'stale_sources': mismatches}},
            'catalog_recipe_keys': sorted(catalog['recipes'])}
    write_json(OUT / 'snapshot.json', data)
    inventory(data)
    print('WALK_ATLAS_SNAPSHOT_PASS', len(active), 'manifests', len(files), 'payloads; no production writes')


def inventory(before):
    originals = {src: load(OUT / 'manifest_before' / src[6:]) for src in before['active']}
    affected = {src: changed_parts(v) for src, v in originals.items() if changed_parts(v)}
    iron = []
    base = originals[BASE]
    clips = [c for c in base['clips'] if c['id'] in (
        'idle', 'combat_idle', 'walk', 'run', 'combat_walk', 'combat_run', 'attack_jump_heavy',
        'guard', 'guard_raise', 'guard_lower', 'guard_break', 'hit', 'hit_back', 'knockback',
        'down', 'unconscious', 'get_up', 'rescue', 'walk_slash')]
    count = sum(c['samples'] for c in clips) * len(base['directions'])
    check(len(clips) == 19 and count == 584, 'Original plan changed; review bake commands')
    for number in range(1, 8):
        actual = copy.deepcopy(base['appearance'])
        for bit, (slot, part) in enumerate([('helmet', 'helmet_western_iron_01'),
                                          ('armor', 'armor_western_iron_01'), ('boots', 'boots_western_iron_01')]):
            if number & (1 << bit):
                actual['parts'][slot] = part
        old_files = sorted((ROOT / f'output/western_iron_atlas_20260913/full/iron{number}').glob('**/manifest.json'))
        iron.append({'key': f'standard_soldier_v2/iron{number}/m31', 'iron': number, 'mask': 31,
                     'appearance': actual, 'changed_parts': changed_parts({'appearance': actual}),
                     'formally_admitted_at_task_before': False, 'rgba_frames_required': count,
                     'dye_frames_required': count, 'legacy_dye_exists': False,
                     'historical_batches': {resource(f): record(f) for f in old_files},
                     'action': 'FRESH_RGBA_AND_DYE_REQUIRED; never recertify historical pixels'})
    mixed = []
    cache = PREVIOUS / 'integration/cache'
    for file in sorted(cache.glob('*/*/manifest.json')):
        v = load(file)
        mixed.append({'manifest': resource(file), 'file': record(file),
                      'appearance': v['appearance'], 'changed_parts': changed_parts(v),
                      'action': 'FRESH_RGBA_AND_DYE_REQUIRED' if changed_parts(v) else 'SOURCE_NAMESPACE_INVALIDATES; no retagging',
                      'not_formal_legacy_manifest': True})
    write_json(OUT / 'affected.json', {
        'scope': CHANGED, 'admitted_manifests': len(before['active']), 'admitted_changed_pixels': affected,
        'unaffected_candidates_pending_gpu': sorted(set(before['active']) - set(affected)),
        'formal_equipment_recipes': 32, 'historical_workplan_recipes': 39,
        'western_iron_rebake': iron, 'mixed_test_caches_not_user_cache_inventory': mixed,
        'excluded_armed_rider': EXCLUDED, 'new_admission_granted': False,
        'remaining_gate': 'Final source freeze + full before/after native GPU evidence + main review; no publication by this script'})


def verify_unchanged(before):
    for src, expected in before['active'].items():
        check(digest(path(src)) == expected, 'Concurrent formal atlas change: ' + src)
        check(digest(OUT / 'manifest_before' / src[6:]) == expected, 'Snapshot changed: ' + src)
    for src, info in {**before['payloads'], **before['baseline_files']}.items():
        check(record(path(src)) == info, 'Preserved payload/baseline changed: ' + src)
    for src, item in before['excluded'].items():
        check(record(path(src)) == item['file'], 'Excluded historical rider changed')
    current = {src: digest(path(src)) for src in before['sources']}
    check(all(src in ALLOWED or current[src] == expected for src, expected in before['sources'].items()),
          'Unrelated source changed; no source refresh allowed')
    return current


def report_path(prefix):
    return OUT / (prefix + '_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '.json')


def revision_root(phase):
    check(isinstance(phase, str) and re.fullmatch(r'after_[a-z0-9][a-z0-9_-]{0,47}', phase)
          and phase != 'after_fixed', 'Use a fresh safe after revision, never withdrawn after_fixed')
    return OUT / 'after_revision' / phase


def routing_audit(write=False):
    original = OUT / 'capture_regression.gd'
    parent = ROOT / 'scripts/tests/cloth_hats_regression.gd'
    revision = OUT / 'capture_revision.gd'
    check(digest(original) == BEFORE_WRAPPER_MD5 and digest(parent) == PARENT_SAMPLER_MD5,
          'Original before wrapper/sampler bytes must remain immutable')
    code = original.read_text(encoding='utf-8-sig')
    lock = code[code.index('func _lock_inputs()'):code.index('func _verify_inputs()')].strip()
    lock = lock.replace('func _lock_inputs() -> bool:\n', '''func _lock_inputs() -> bool:
\tif FileAccess.get_md5(OLD_WRAPPER) != OLD_WRAPPER_MD5 or FileAccess.get_md5(REGRESSION_PARENT) != OLD_PARENT_MD5:
\t\tpush_error("Immutable original sampling source changed")
\t\treturn false
\tif FileAccess.file_exists(TASK_ATLAS+"/after_revision/"+phase+"/WITHDRAWN.json"):
\t\tpush_error("This revision freeze was withdrawn")
\t\treturn false
''')
    lock = lock.replace('if phase == "after_fixed":', 'if phase.begins_with("after_"):')
    lock = lock.replace('TASK_ATLAS+"/after_sources.json"', 'TASK_ATLAS+"/after_revision/"+phase+"/after_sources.json"')
    lock = lock.replace('freeze.get("formal_published") != true:',
                        'freeze.get("formal_published") != true or freeze.get("revision") != phase:')
    run = code[code.index('func _run()'):].strip()
    run = run.replace('assert(args.size() in [3, 4] and args[0] in ["before_fixed", "after_fixed"] and args[1] in ["male", "female"] and args[2] == "--equipment-limits")',
                      '''var revision_pattern := RegEx.create_from_string("^after_[a-z0-9][a-z0-9_-]{0,47}$")
\tassert(args.size() in [3, 4] and args[1] in ["male", "female"] and args[2] == "--equipment-limits")
\tassert(revision_pattern.search(args[0]) != null and args[0] != "after_fixed", "Use a fresh named after revision")''')
    run = run.replace('OUT+"/atlas/"+regression_subdir+"/"+phase+"/"+sex',
                      'OUT+"/atlas/after_revision/"+phase+"/"+regression_subdir+"/"+sex')
    header = '''extends "res://output/equipment_walk_fix_20260919/atlas/capture_regression.gd"
## Routing-only revision: inherited sampling/camera/report helpers remain frozen.
const OLD_WRAPPER := "res://output/equipment_walk_fix_20260919/atlas/capture_regression.gd"
const OLD_WRAPPER_MD5 := "6d007c4fd60295f2591b750be56f5d4f"
const OLD_PARENT_MD5 := "93b04e5a53d8871980088d522a72dca0"
'''
    expected = header.strip() + '\n\n' + lock + '\n\n' + run
    check(revision.read_text(encoding='utf-8-sig').strip() == expected,
          'Revision wrapper changed more than audited parameter/folder/freeze routing')
    result = {'schema_version': 1, 'status': 'ROUTING_ONLY_STATIC_PROOF_PASS',
              'before_wrapper': record(original), 'original_sampler': record(parent), 'revision_wrapper': record(revision),
              'before_wrapper_unchanged': True, 'sampling_body_unchanged': True,
              'inherited_methods_unchanged': ['sample_image', 'finish_report', 'wagon_samples', 'neutral', 'frame_camera', 'settle', '_verify_inputs'],
              'gpu_parser_or_execution_verified': False, 'scope': 'Static source equivalence; no Godot launch'}
    if write:
        write_json(report_path('routing_audit'), result)
        print('WALK_ATLAS_ROUTING_AUDIT_PASS: frozen original + routing-only revision; no Godot launched')
    return result


def capture_evidence(phase):
    """Verify real fixed-sample PNGs; deliberately not atlas pages or all frames."""
    before = load(OUT / 'snapshot.json')
    sources = before['sources']
    check(digest(OUT / 'capture_regression.gd') == BEFORE_WRAPPER_MD5
          and digest(ROOT / 'scripts/tests/cloth_hats_regression.gd') == PARENT_SAMPLER_MD5, 'Frozen sampling source changed')
    capture_root = OUT
    wrapper = OUT / 'capture_regression.gd'
    if phase != 'before_fixed':
        capture_root = revision_root(phase)
        check(not (capture_root / 'WITHDRAWN.json').exists(), 'This after revision was withdrawn')
        routing_audit()
        wrapper = OUT / 'capture_revision.gd'
        freeze = load(capture_root / 'after_sources.json')
        check(freeze.get('revision') == phase and freeze.get('formal_published') is True
              and freeze['snapshot_md5'] == digest(OUT / 'snapshot.json'),
              'After requires main-owned formal freeze')
        sources = freeze['source_fingerprints']
        check(set(sources) == set(before['sources']), 'After source set differs')
        check(all(digest(path(src)) == expected for src, expected in sources.items()), 'Formal source changed after capture')
    for src, info in before['baseline_files'].items():
        check(record(path(src)) == info, 'Immutable baseline changed: ' + src)
    results, samples, cases = {}, {}, {}
    for section, count in [('regression', 153), ('regression_wagon', 72)]:
        for sex in ('male', 'female'):
            folder = OUT / section / phase / sex if phase == 'before_fixed' else capture_root / section / sex
            value = load(folder / 'result.json')
            check(value['complete'] is True and value['phase'] == phase and value['sex'] == sex
                  and value['count'] == len(value['samples']) == len(value['cases']) == count, 'Incomplete capture')
            check(value['snapshot_md5'] == digest(OUT / 'snapshot.json') and value['source_fingerprints'] == sources,
                  'Capture does not use exact task sources')
            check(value['wrapper_md5'] == digest(wrapper)
                  and value['parent_md5'] == digest(ROOT / 'scripts/tests/cloth_hats_regression.gd'), 'Capture code changed')
            check(value['editor_md5'] == sources[EDITOR]
                  and value['glb_md5'] == sources[MODEL_ROOT + f'standard_anime_{sex}_character_pack.glb']
                  and value['dye_md5'] == sources['res://scripts/ui/equipment_dye.gd'], 'Source digest mismatch')
            # Reuse only the previous suite's label set, never its old pixel hashes.
            labels = set(load(PREVIOUS / section / 'before_fixed' / sex / 'result.json')['samples'])
            check(set(value['samples']) == set(value['cases']) == labels, 'Original representative sample set changed')
            check({p.stem for p in folder.glob('*.png')} == labels, 'PNG set differs from capture report')
            matching = []
            for result_file in (OUT / 'godot_runs').glob('*/result.json'):
                run = load(result_file)
                args = run['arguments']
                if (phase in args and sex in args and
                    resource(wrapper) in args and
                    ('--wagon-only' in args) == (section == 'regression_wagon') and run['status'] == 'PASS'):
                    matching.append((result_file, run))
            check(len(matching) == 1, 'Need one exact canonical PASS per capture case')
            result_file, run = matching[0]
            check(run['mode'] == 'visual' and run['exit_code'] == 0 and not run['timed_out']
                  and not run['failure'] and not run['missing_outputs'], 'Not a clean bounded visual capture')
            marker = f'WALK_ATLAS_GPU_CAPTURE_PASS {phase} {sex} {section} samples={count}'
            check(marker in (result_file.parent / 'stdout.log').read_text(encoding='utf-8-sig'), 'Capture completion marker missing')
            results[section + '/' + sex] = {'run': result_file.parent.name, 'seconds': run['duration_seconds'],
                'capture_report': resource(folder / 'result.json'), 'capture_file': record(folder / 'result.json'),
                'logs': {name: record(result_file.parent / name)
                         for name in ('result.json', 'stdout.log', 'stderr.log', 'combined.log')}}
            for label in sorted(labels):
                pixels = pixel_record(folder / (label + '.png'))
                check(pixels[:2] == [[256, 320], 'RGBA'] and pixels[2] == value['samples'][label], 'PNG/report raw RGBA mismatch')
                key = section + '/' + sex + '/' + label
                samples[key] = pixels[2]
                cases[key] = value['cases'][label]
    check(len(samples) == 450, 'Expected exactly 450 representative samples')
    return {'schema_version': 1, 'phase': phase, 'snapshot_md5': digest(OUT / 'snapshot.json'),
            'source_fingerprints': sources, 'runs': results, 'samples': samples, 'cases': cases,
            'count': 450, 'scope': 'representative_fixed_153_plus_72_per_sex',
            'full_atlas_frame_proof': False, 'native_preservation_proof_required': True, 'published': False}


def capture_summary():
    evidence = capture_evidence('before_fixed')
    targets = {key: changed_parts({'appearance': case['appearance']}) for key, case in evidence['cases'].items()
               if changed_parts({'appearance': case['appearance']})}
    check(len(targets) == 82, 'Review actual before sample equipment scope')
    evidence['control_count'] = 368
    evidence['target_samples_not_equivalence_evidence'] = targets
    evidence['status'] = 'BEFORE_CAPTURE_VERIFIED_AFTER_PENDING'
    write_json(report_path('before_evidence'), evidence)
    print('WALK_ATLAS_BEFORE_EVIDENCE_PASS: 450 actual RGBA PNGs; four canonical PASS; after/native proof pending')


def compare_gpu(write=True, after_phase='after_v4'):
    before, after = capture_evidence('before_fixed'), capture_evidence(after_phase)
    check(before['cases'] == after['cases'], 'Actual appearances, poses or sample times changed')
    control, targets, unexpected = [], {}, []
    for key, old in before['samples'].items():
        changed = changed_parts({'appearance': before['cases'][key]['appearance']})
        if changed:
            targets[key] = {'parts': changed, 'pixels_changed': old != after['samples'][key],
                            'before': old, 'after': after['samples'][key]}
        else:
            control.append(key)
            if old != after['samples'][key]:
                unexpected.append(key)
    # The historical representative suite defaults to helmet_leather_01, so
    # face/hair/cloth samples also change. Classify actual appearances, not names.
    check(len(control) == 368 and len(targets) == 82, 'Review changed sample scope; no silent filtering')
    result = {'schema_version': 1, 'status': 'UNEXPECTED_PIXEL_CHANGE' if unexpected else 'GPU_CONTROLS_PASS_NATIVE_REVIEW_PENDING',
              'after_phase': after_phase, 'routing_audit': routing_audit(),
              'snapshot_md5': before['snapshot_md5'], 'source_before': before['source_fingerprints'],
              'source_after': after['source_fingerprints'], 'before_runs': before['runs'], 'after_runs': after['runs'],
              'representative_samples_per_phase': 450, 'control_samples': control, 'control_count': 368,
              'target_samples_not_equivalence_evidence': targets, 'unexpected_changes': unexpected,
              'scope': before['scope'], 'full_atlas_frame_proof': False,
              'native_preservation_proof_required': True, 'published': False}
    if write:
        target = report_path('gpu_comparison')
        write_json(target, result)  # Preserve a failed comparison too.
        print('WALK_ATLAS_GPU_COMPARISON', result['status'], resource(target))
    return result


def preflight(evidence_path=None, after_phase='after_v4'):
    before = load(OUT / 'snapshot.json')
    current = verify_unchanged(before)
    check(not load(OUT / 'affected.json')['admitted_changed_pixels'], 'Affected legacy recipe requires true rebake')
    blockers = ['Main must freeze formal sources and supply current representative before/after GPU evidence',
                'Main must verify native GLB preservation for all unmodified mesh/rig/animation/material fields',
                'No publication mode: final source update remains main-owned']
    if evidence_path:
        evidence = load(path(evidence_path))
        check(evidence == compare_gpu(write=False, after_phase=after_phase), 'Comparison evidence changed or does not describe actual captures')
        check(evidence['source_after'] == current and not evidence['unexpected_changes'], 'Sources/pixels are not ready for review')
        blockers.pop(0)
    report = {'status': 'GPU_VERIFIED_NATIVE_REVIEW_PENDING' if evidence_path else 'BLOCKED_PENDING_AFTER_GPU',
              'published': False, 'after_phase': after_phase, 'snapshot_md5': digest(OUT / 'snapshot.json'), 'current_sources': current,
              'changed_sources': {s: current[s] for s in current if current[s] != before['sources'][s]},
              'unchanged_formal_manifests': len(before['active']), 'blockers': blockers,
              'gpu_evidence': evidence_path, 'gpu_scope': '450 representative samples, 368 unchanged controls, 82 target samples by actual appearance',
              'full_atlas_frame_proof': False, 'eligible_for_source_only_update': 0, 'changed_pixels_retagged': 0,
              'required_update_scope_after_main_native_review': ['source_fingerprints', 'source_manifest_md5', 'task provenance stamp only'],
              'forbidden_update_scope': ['frames', 'appearance', 'clips', 'directions', 'pages', 'RGBA payloads', 'dye payloads', 'excluded armed rider']}
    write_json(report_path('preflight'), report)
    print('WALK_ATLAS_PREFLIGHT', report['status'], 'published=False')
    return 2  # A GPU comparison alone is intentionally never source-publication proof.


def pixel_record(file):
    # Installed Pillow decodes evidence only. It never generates/edits imagery.
    from PIL import Image
    with Image.open(file) as image:
        image.load()
        return [list(image.size), image.mode, hashlib.sha256(image.tobytes()).hexdigest()]


def self_test():
    base = {'appearance': {'parts': {'armor': 'armor_light_leather_01', 'helmet': 'none', 'boots': 'boots_leather_01'}}}
    check(not changed_parts(base), 'Unchanged recipe falsely affected')
    for slot, parts in CHANGED.items():
        for part in parts:
            case = copy.deepcopy(base)
            case['appearance']['parts'][slot] = part
            check(changed_parts(case) == [slot + ':' + part], 'Missed changed part')
    check(parent_of(CATALOG, {'source_manifest_md5': 'test'}) == BASE, 'Catalog parent lost')
    for invalid in ['res://../outside', 'user://cache', 'res://assets/../scripts/test']:
        try:
            path(invalid)
        except ValueError:
            continue
        raise ValueError('Unsafe path accepted: ' + invalid)
    check('--publish' not in parser().format_help(), 'Must never expose a publication switch')
    for invalid in ['after_fixed', '../after_v4', 'after_v4/extra', 'before_fixed', 'after_', 'after_V4']:
        try:
            revision_root(invalid)
        except ValueError:
            continue
        raise ValueError('Unsafe/withdrawn revision accepted: ' + invalid)
    check(revision_root('after_v4') == OUT / 'after_revision/after_v4', 'Wrong revision routing')
    print('WALK_ATLAS_SELF_TEST_PASS: nine changed IDs; unchanged recipe; implicit parent; path rejection; no publisher')


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    modes = result.add_mutually_exclusive_group(required=True)
    modes.add_argument('--snapshot', action='store_true')
    modes.add_argument('--preflight', action='store_true')
    modes.add_argument('--self-test', action='store_true')
    modes.add_argument('--capture-summary', action='store_true')
    modes.add_argument('--compare-gpu', action='store_true')
    modes.add_argument('--routing-audit', action='store_true')
    result.add_argument('--evidence', help='res:// task evidence JSON for main review')
    result.add_argument('--after-phase', default='after_v4', help='Named final revision; default after_v4')
    return result


if __name__ == '__main__':
    args = parser().parse_args()
    check(not args.evidence or args.preflight, 'Evidence is only used by preflight')
    if args.snapshot:
        snapshot()
    elif args.self_test:
        self_test()
    elif args.capture_summary:
        capture_summary()
    elif args.compare_gpu:
        raise SystemExit(1 if compare_gpu(after_phase=args.after_phase)['unexpected_changes'] else 0)
    elif args.routing_audit:
        routing_audit(write=True)
    else:
        raise SystemExit(preflight(args.evidence, after_phase=args.after_phase))
