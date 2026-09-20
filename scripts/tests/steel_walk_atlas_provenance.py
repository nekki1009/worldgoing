"""Read-only steel/Mingguang atlas evidence adapter; publication stays main-owned.

Reuses the prior audited payload, appearance and GPU validators in an isolated
module instance. Only task constants/routing and dynamic target classification
differ. Never writes formal assets, manifests, or previous evidence.
"""
import argparse
import importlib.util
import json
from pathlib import Path

SPEC = importlib.util.spec_from_file_location('_steel_walk_audit', Path(__file__).with_name('equipment_walk_atlas_provenance.py'))
a = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(a)
OLD = a.TASK
OLD_BEFORE_WRAPPER_MD5 = a.BEFORE_WRAPPER_MD5
a.TASK = a.ROOT / 'output/steel_mingguang_walk_20260919'
a.OUT = a.TASK / 'atlas'
a.CHANGED = {'armor': ['armor_chinese_steel_01', 'armor_western_steel_01', 'armor_mingguang_01']}
a.ALLOWED = {a.MODEL_ROOT + f'standard_anime_{sex}_character_pack.glb' for sex in ('male', 'female')}
ROOT, TASK, OUT, CHANGED, ALLOWED = a.ROOT, a.TASK, a.OUT, a.CHANGED, a.ALLOWED
load, digest, record, path, resource = a.load, a.digest, a.record, a.path, a.resource
check, write_json, verify_unchanged = a.check, a.write_json, a.verify_unchanged
parent_of, changed_parts = a.parent_of, a.changed_parts


def routing_audit(write=False):
    """Copies differ only by task path; all sampling and cameras stay frozen."""
    files = {}
    for name in ('capture_regression.gd', 'capture_revision.gd'):
        original, routed = OLD / 'atlas' / name, OUT / name
        expected = original.read_text(encoding='utf-8-sig').replace('equipment_walk_fix_20260919', 'steel_mingguang_walk_20260919')
        if name == 'capture_revision.gd':
            expected = expected.replace(OLD_BEFORE_WRAPPER_MD5, digest(OUT / 'capture_regression.gd'))
        check(routed.read_text(encoding='utf-8-sig').strip() == expected.strip(), 'Non-routing sampler edit: ' + name)
        files[name] = {'original': record(original), 'routed': record(routed)}
    check(digest(ROOT / 'scripts/tests/cloth_hats_regression.gd') == a.PARENT_SAMPLER_MD5, 'Sampler parent changed')
    result = {'status': 'ROUTING_ONLY_STATIC_PROOF_PASS', 'files': files, 'sampling_body_unchanged': True,
              'gpu_parser_or_execution_verified': False}
    if write:
        write_json(a.report_path('routing_audit'), result)
    return result


def snapshot():
    check(not (OUT / 'snapshot.json').exists(), 'Never replace task baseline')
    proof_path = OLD / 'atlas/publication.json'
    proof, previous = load(proof_path), load(OLD / 'atlas/snapshot.json')
    active, sources = proof['published_md5'], proof['current_sources']
    check(proof['published'] is True and len(active) == 260 and set(active) == set(previous['active']), 'Admission drift')
    check(len(sources) == 22, 'Source inventory changed')
    for src, expected in sources.items():
        check(digest(a.baseline_source(src)) == expected, 'Baseline source mismatch: ' + src)
        if src not in ALLOWED:
            a.preserve(path(src), OUT / 'source_before' / src[6:])
    manifests, payloads = {}, {}
    for src, expected in active.items():
        check(digest(path(src)) == expected, 'Formal manifest mismatch: ' + src)
        value = load(path(src))
        check(value.get('source_fingerprints') and all(sources.get(s) == h for s, h in value['source_fingerprints'].items()), 'Manifest sources mismatch')
        parent = parent_of(src, value)
        if parent:
            check(parent in active and value['source_manifest_md5'] == active[parent], 'Parent mismatch')
        if 'mask_path' in value:
            pv = load(path(parent))
            check(value['complete'] and value['appearance'] == pv['appearance'] and value['frame_count'] == len(pv['frames']), 'Dye coverage mismatch')
        a.preserve(path(src), OUT / 'manifest_before' / src[6:])
        current_payloads = a.payloads(src, value)
        for s, info in current_payloads.items():
            check(previous['payloads'].get(s) == info, 'Previous payload changed: ' + s)
            payloads[s] = info
        manifests[src] = {'file': record(path(src)), 'parent': parent, 'appearances': a.appearances(value),
                          'changed_parts': changed_parts(value), 'payloads': list(current_payloads)}
    check(payloads == previous['payloads'] and len(payloads) == 470, 'Payload inventory mismatch')
    catalog = load(path(a.CATALOG))
    check(sorted(catalog['recipes']) == previous['catalog_recipe_keys'], 'Catalog changed')
    baseline = {resource(p): record(p) for p in sorted((TASK / 'baseline').iterdir())
                if p.name.startswith('standard_anime_') or p.name == 'human_character_3d_editor.gd.txt'}
    check(len(baseline) == 7, 'Expected six models plus editor backup')
    check(record(path(a.EXCLUDED)) == previous['excluded'][a.EXCLUDED]['file'], 'Excluded rider changed')
    a.preserve(path(a.EXCLUDED), OUT / 'excluded_before' / a.EXCLUDED[6:])
    a.preserve(proof_path, OUT / 'previous_260_proof.json')
    result = {'schema_version': 1, 'published': False, 'active': active, 'sources': sources,
              'baseline_files': baseline, 'manifests': manifests, 'payloads': payloads,
              'excluded': previous['excluded'], 'catalog_recipe_keys': previous['catalog_recipe_keys'],
              'prior_proof': record(proof_path)}
    verify_unchanged(result)
    write_json(OUT / 'snapshot.json', result)
    affected = {s: v['changed_parts'] for s, v in manifests.items() if v['changed_parts']}
    write_json(OUT / 'affected.json', {'scope': CHANGED, 'admitted_manifests': len(active),
               'admitted_changed_pixels': affected, 'new_admission_granted': False})
    print('STEEL_WALK_SNAPSHOT_PASS', len(active), 'manifests', len(payloads), 'payloads; affected=', len(affected))


def reuse_before():
    """Validate previous final GPU evidence now, retain exact dependency hashes.

    This is reuse of four prior native runs, NOT four new executions.
    """
    spec = importlib.util.spec_from_file_location('_prior_walk_audit', Path(__file__).with_name('equipment_walk_atlas_provenance.py'))
    old = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(old)
    evidence = old.capture_evidence('after_v6')
    snap = load(OUT / 'snapshot.json')
    check(evidence['source_fingerprints'] == snap['sources'], 'Previous final sources do not match current baseline')
    deps = {}
    for file in (OLD / 'atlas/after_revision/after_v6').rglob('*'):
        if file.is_file():
            deps[resource(file)] = record(file)
    for run in evidence['runs'].values():
        for name in run['logs']:
            file = OLD / 'atlas/godot_runs' / run['run'] / name
            deps[resource(file)] = record(file)
    for file in [OLD / 'atlas/capture_regression.gd', OLD / 'atlas/capture_revision.gd', OLD / 'atlas/snapshot.json']:
        deps[resource(file)] = record(file)
    targets = {k: changed_parts({'appearance': c['appearance']}) for k, c in evidence['cases'].items()
               if changed_parts({'appearance': c['appearance']})}
    write_json(OUT / 'before_reuse.json', {'status': 'EXACT_SOURCE_REUSE_VERIFIED_NOT_RERUN',
        'task_snapshot_md5': digest(OUT / 'snapshot.json'), 'evidence': evidence, 'dependencies': deps,
        'control_count': len(evidence['samples']) - len(targets), 'target_samples': targets,
        'native_source_proof': 'Both complete GLB bytes, Editor and all 22 sources match task baseline',
        'new_gpu_runs': 0, 'published': False})
    print('STEEL_WALK_BEFORE_REUSE_PASS controls=', 450 - len(targets), 'targets=', len(targets), 'new_runs=0')


def capture_evidence(phase):
    if phase == 'before_fixed' and (OUT / 'before_reuse.json').exists():
        reused = load(OUT / 'before_reuse.json')
        check(reused['task_snapshot_md5'] == digest(OUT / 'snapshot.json'), 'Reuse snapshot changed')
        for src, expected in reused['dependencies'].items():
            check(record(path(src)) == expected, 'Reused evidence changed: ' + src)
        check(reused['evidence']['source_fingerprints'] == load(OUT / 'snapshot.json')['sources'], 'Reuse source drift')
        return reused['evidence']
    a.routing_audit = routing_audit
    a.BEFORE_WRAPPER_MD5 = digest(OUT / 'capture_regression.gd')
    return a.capture_evidence(phase)


def compare_gpu(write=True, after_phase='after_v1'):
    before, after = capture_evidence('before_fixed'), capture_evidence(after_phase)
    check(before['cases'] == after['cases'], 'Actual appearances, poses or sample times changed')
    controls, targets, unexpected = [], {}, []
    for key, old in before['samples'].items():
        parts = changed_parts({'appearance': before['cases'][key]['appearance']})
        if parts:
            targets[key] = {'parts': parts, 'pixels_changed': old != after['samples'][key], 'before': old, 'after': after['samples'][key]}
        else:
            controls.append(key)
            if old != after['samples'][key]:
                unexpected.append(key)
    result = {'status': 'UNEXPECTED_PIXEL_CHANGE' if unexpected else 'GPU_CONTROLS_PASS_NATIVE_REVIEW_PENDING',
        'after_phase': after_phase, 'routing_audit': routing_audit(), 'snapshot_md5': digest(OUT / 'snapshot.json'),
        'source_before': before['source_fingerprints'], 'source_after': after['source_fingerprints'],
        'before_runs': before['runs'], 'after_runs': after['runs'], 'before_reused_not_rerun': (OUT / 'before_reuse.json').exists(),
        'representative_samples_per_phase': len(before['samples']), 'control_samples': controls, 'control_count': len(controls),
        'target_samples_not_equivalence_evidence': targets, 'unexpected_changes': unexpected,
        'full_atlas_frame_proof': False, 'native_preservation_proof_required': True, 'published': False}
    if write:
        target = a.report_path('gpu_comparison')
        write_json(target, result)
        print(result['status'], resource(target))
    return result


def self_test():
    for part in CHANGED['armor']:
        check(changed_parts({'appearance': {'parts': {'armor': part}}}) == ['armor:' + part], 'Missed armor')
    check(not changed_parts({'appearance': {'parts': {'armor': 'armor_iron_01', 'helmet': 'helmet_leather_01'}}}), 'Old target leaked')
    check(len(ALLOWED) == 2 and a.EDITOR not in ALLOWED, 'Editor must remain unchanged')
    routing_audit()
    print('STEEL_WALK_SELF_TEST_PASS; three armor IDs, two GLBs, frozen routing, no publisher')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    for mode in ('snapshot', 'reuse-before', 'self-test', 'compare-gpu', 'verify-unchanged'):
        modes.add_argument('--' + mode, action='store_true')
    parser.add_argument('--after-phase', default='after_v1')
    args = parser.parse_args()
    try:
        if args.snapshot: snapshot()
        elif args.reuse_before: reuse_before()
        elif args.self_test: self_test()
        elif args.verify_unchanged:
            verify_unchanged(load(OUT / 'snapshot.json'))
            print('STEEL_WALK_PRESERVATION_PASS')
        else:
            raise SystemExit(1 if compare_gpu(after_phase=args.after_phase)['unexpected_changes'] else 0)
    except Exception as exc:
        write_json(a.report_path('failure'), {'error': repr(exc), 'arguments': vars(args), 'published': False})
        raise
