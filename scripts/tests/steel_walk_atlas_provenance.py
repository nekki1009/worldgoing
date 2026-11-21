"""Read-only steel/Mingguang atlas evidence adapter; publication stays main-owned.

Reuses the prior audited payload, appearance and GPU validators in an isolated
module instance. Only task constants/routing and dynamic target classification
differ. Never writes formal assets, manifests, or previous evidence.
"""
import argparse
import importlib.util
import json
import re
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
FRESH_BASELINE = 'baseline_472'
original_revision_root = a.revision_root


def revision_root(phase):
    return OUT / 'after_revision' / phase if phase == FRESH_BASELINE else original_revision_root(phase)


a.revision_root = revision_root


def routing_audit(write=False):
    """Copies differ only by task path; all sampling and cameras stay frozen."""
    files = {}
    for name in ('capture_regression.gd', 'capture_revision.gd'):
        original, routed = OLD / 'atlas' / name, OUT / name
        expected = original.read_text(encoding='utf-8-sig').replace('equipment_walk_fix_20260919', 'steel_mingguang_walk_20260919')
        if name == 'capture_revision.gd':
            expected = expected.replace(OLD_BEFORE_WRAPPER_MD5, digest(OUT / 'capture_regression.gd'))
            expected = expected.replace('if phase.begins_with("after_"):',
                                        'if phase.begins_with("after_") or phase == "baseline_472":')
            expected = expected.replace('^after_[a-z0-9][a-z0-9_-]{0,47}$',
                                        '^(after_[a-z0-9][a-z0-9_-]{0,47}|baseline_472)$')
            expected = expected.replace('\t\t_locked_sources = freeze.source_fingerprints.duplicate()\n',
                '\t\t_locked_sources = freeze.source_fingerprints.duplicate()\n'
                '\t\tif phase == "baseline_472" and (freeze.get("baseline_capture") != true or _locked_sources != _snapshot.sources):\n'
                '\t\t\tpush_error("Fresh baseline must freeze all 22 original formal sources")\n'
                '\t\t\treturn false\n')
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


def freeze_baseline():
    """Freeze current formal baseline; does not launch a capture or rehash atlas payloads."""
    snap = load(OUT / 'snapshot.json')
    current = {src: digest(path(src)) for src in snap['sources']}
    check(len(current) == 22 and current == snap['sources'], 'Formal sources no longer equal original baseline')
    write_json(revision_root(FRESH_BASELINE) / 'after_sources.json', {
        'revision': FRESH_BASELINE, 'baseline_capture': True, 'formal_published': True,
        'snapshot_md5': digest(OUT / 'snapshot.json'), 'source_fingerprints': current,
        'expected_engine': '4.7.2', 'prior_inherited_evidence_used': False})
    print('STEEL_WALK_FRESH_BASELINE_FROZEN_NOT_CAPTURED')


def runtime_identity(run_dir):
    run = load(run_dir / 'result.json')
    binary = load(run_dir / 'runtime_executable.json')
    lines = (run_dir / 'stdout.log').read_text(encoding='utf-8-sig').splitlines()
    engine = [line for line in lines if line.startswith('Godot Engine v')]
    device = [line for line in lines if ' - Using Device #' in line]
    check(len(engine) == len(device) == 1 and engine[0].startswith('Godot Engine v4.7.2.'),
          'Fresh captures require actual Godot 4.7.2 version and renderer/device logs')
    check(binary['unchanged_during_run'] is True and len(binary['files_sha256']) == 2,
          'Missing console/engine binary identity or executable changed during run')
    executable = Path(binary['executable']).resolve()
    check(executable == Path(run['executable']).resolve(), 'Canonical/runtime executable mismatch')
    expected = {executable, executable.with_name(executable.name.replace('_console.exe', '.exe'))}
    check({Path(p).resolve() for p in binary['files_sha256']} == expected,
          'Runtime binary inventory differs')
    check(all(re.fullmatch('[0-9a-f]{64}', h) for h in binary['files_sha256'].values()), 'Invalid runtime binary hash')
    return {'engine': engine[0], 'renderer_device': device[0], 'executable': str(executable),
            'files_sha256': binary['files_sha256']}


def same_runtime(before, after):
    check(before['runtime_identity'] == after['runtime_identity'],
          'Engine build, binary, renderer or GPU differs; cannot claim RGBA equivalence')


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
    if phase == FRESH_BASELINE:
        freeze = load(revision_root(phase) / 'after_sources.json')
        check(freeze.get('baseline_capture') is True
              and freeze['source_fingerprints'] == load(OUT / 'snapshot.json')['sources'],
              'Fresh baseline source freeze differs from immutable task baseline')
    # The fresh baseline was captured from formal files before publication.
    # After publication validate its two old GLBs against the immutable copies;
    # the capture report and source lock still bind all 22 original sources.
    original_path = a.path
    try:
        if phase == FRESH_BASELINE:
            a.path = lambda src: TASK / 'baseline' / Path(src).name if src in ALLOWED else original_path(src)
        result = a.capture_evidence(phase)
    finally:
        a.path = original_path
    identities = []
    for run in result['runs'].values():
        run_dir = OUT / 'godot_runs' / run['run']
        identities.append(runtime_identity(run_dir))
        run['logs']['runtime_executable.json'] = record(run_dir / 'runtime_executable.json')
    check(all(identity == identities[0] for identity in identities), 'Runtime drift within capture phase')
    result['runtime_identity'] = identities[0]
    return result


def compare_gpu(write=True, after_phase='after_v5', before_phase=FRESH_BASELINE):
    check(before_phase == FRESH_BASELINE, 'New comparisons cannot use inherited Godot 4.6.2 evidence')
    check(after_phase != before_phase, 'Before and after must be distinct captures')
    before, after = capture_evidence(before_phase), capture_evidence(after_phase)
    same_runtime(before, after)
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
        'before_phase': before_phase, 'after_phase': after_phase,
        'runtime_identity': before['runtime_identity'], 'routing_audit': routing_audit(), 'snapshot_md5': digest(OUT / 'snapshot.json'),
        'source_before': before['source_fingerprints'], 'source_after': after['source_fingerprints'],
        'before_runs': before['runs'], 'after_runs': after['runs'], 'before_reused_not_rerun': False,
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
    check(revision_root(FRESH_BASELINE) == OUT / 'after_revision/baseline_472', 'Fresh baseline routing')
    same_runtime({'runtime_identity': {'engine': '4.7.2'}}, {'runtime_identity': {'engine': '4.7.2'}})
    for field in ('engine', 'files_sha256', 'renderer_device'):
        try:
            same_runtime({'runtime_identity': {field: 'before'}}, {'runtime_identity': {field: 'after'}})
        except (ValueError, AssertionError):
            pass
        else:
            raise AssertionError('Runtime counterexample accepted: ' + field)
    try:
        compare_gpu(write=False, before_phase='before_fixed')
    except (ValueError, AssertionError):
        pass
    else:
        raise AssertionError('Inherited before accepted by new comparison')
    print('STEEL_WALK_SELF_TEST_PASS; three armor IDs, two GLBs, frozen routing, no publisher')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    for mode in ('snapshot', 'reuse-before', 'self-test', 'compare-gpu', 'verify-unchanged', 'freeze-baseline'):
        modes.add_argument('--' + mode, action='store_true')
    parser.add_argument('--after-phase', default='after_v5')
    parser.add_argument('--before-phase', default=FRESH_BASELINE)
    args = parser.parse_args()
    try:
        if args.snapshot: snapshot()
        elif args.reuse_before: reuse_before()
        elif args.self_test: self_test()
        elif args.freeze_baseline: freeze_baseline()
        elif args.verify_unchanged:
            verify_unchanged(load(OUT / 'snapshot.json'))
            print('STEEL_WALK_PRESERVATION_PASS')
        else:
            raise SystemExit(1 if compare_gpu(after_phase=args.after_phase, before_phase=args.before_phase)['unexpected_changes'] else 0)
    except Exception as exc:
        write_json(a.report_path('failure'), {'error': repr(exc), 'arguments': vars(args), 'published': False})
        raise
