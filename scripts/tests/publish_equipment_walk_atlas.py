"""Fail-closed source publication for unchanged, already admitted legacy atlases.

Requires native GLB preservation plus real representative GPU comparison.
Never changes pixels, frames, packing, equipment selection or historical riders.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path

import equipment_walk_atlas_provenance as audit
from validate_chinese_cloak_assets import read_glb


def native_proof(revision):
    result = {}
    for sex in ('male','female'):
        name = f'standard_anime_{sex}_character_pack.glb'
        old_path = audit.TASK/'baseline'/name
        current = audit.ROOT/'assets/characters/human/q35'/name
        report = audit.load(audit.TASK/'combined'/revision/sex/'build.json')
        assert audit.digest(current,'sha256') == report['candidate_sha256']['.glb']
        old, old_binary = read_glb(old_path)
        new, new_binary = read_glb(current)
        expected = set(report['glb']['replaced_meshes'])
        assert len(expected) == 30
        assert new_binary[:len(old_binary)] == old_binary
        for key in old:
            if key not in ('meshes','accessors','bufferViews','buffers'):
                assert new[key] == old[key], key
        assert new['accessors'][:len(old['accessors'])] == old['accessors']
        assert new['bufferViews'][:len(old['bufferViews'])] == old['bufferViews']
        buffers = copy.deepcopy(new['buffers'])
        assert len(buffers) == len(old['buffers']) == 1
        buffers[0]['byteLength'] = old['buffers'][0]['byteLength']
        assert buffers == old['buffers']
        assert len(new['meshes']) == len(old['meshes'])
        mesh_names = {n['mesh']:n['name'] for n in old['nodes'] if 'mesh' in n}
        changed = set()
        for i,(a,b) in enumerate(zip(old['meshes'],new['meshes'])):
            if a == b: continue
            name = mesh_names[i]
            assert name in expected, name
            changed.add(name)
            a,b = copy.deepcopy(a),copy.deepcopy(b)
            assert len(a['primitives']) == len(b['primitives'])
            for p,q in zip(a['primitives'],b['primitives']):
                for key in ('attributes','indices'):
                    p.pop(key,None); q.pop(key,None)
            assert a == b, name
        assert changed == expected
        result[sex] = {'before':audit.record(old_path),'after':audit.record(current),
            'changed_mesh_names':sorted(changed),'unchanged_mesh_count':len(old['meshes'])-len(changed),
            'original_binary_bytes_unchanged':len(old_binary),
            'all_other_document_fields_unchanged':True,'allowed_mesh_fields':['attributes','indices']}
    return result


def main(*, audit_module=None, native_validator=None, stamp_key='equipment_walk_revalidation'):
    # Optional task adapter; the original command retains all original defaults.
    audit = audit_module if audit_module is not None else globals()['audit']
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--revision',required=True)
    parser.add_argument('--after-phase',required=True)
    parser.add_argument('--gpu-evidence',required=True)
    parser.add_argument('--publish',action='store_true')
    args = parser.parse_args()
    assert args.revision.isalnum()
    before = audit.load(audit.OUT/'snapshot.json')
    current = audit.verify_unchanged(before)
    assert not audit.load(audit.OUT/'affected.json')['admitted_changed_pixels']
    evidence = audit.load(audit.path(args.gpu_evidence))
    assert evidence == audit.compare_gpu(write=False,after_phase=args.after_phase)
    assert not evidence['unexpected_changes'] and evidence['source_after'] == current
    native = (native_validator or native_proof)(args.revision)
    assert audit.digest(audit.path(audit.EDITOR),'sha256') == '2363b0bcf74d213e8dcb8360140de1bc5b5f98824003c05bfff5eb4d86c0b573'
    # Shader changes are reviewed separately; no additional production source
    # may drift outside the two model files and hair-mask owner.
    assert set(s for s in current if current[s] != before['sources'][s]) == audit.ALLOWED
    pending = set(before['active'])
    encoded,hashes = {},{}
    while pending:
        ready = False
        for src in sorted(pending):
            value = audit.load(audit.OUT/'manifest_before'/src[6:])
            parent = audit.parent_of(src,value)
            if parent in pending: continue
            updated = copy.deepcopy(value)
            updated['source_fingerprints'] = {s:current[s] for s in value['source_fingerprints']}
            if parent: updated['source_manifest_md5'] = hashes[parent]
            updated[stamp_key] = {'rebaked':False,
                'representative_control_pairs':evidence['control_count'],
                'full_atlas_frame_proof':False,'native_unselected_data_unchanged':True,
                'evidence':args.gpu_evidence,'old_manifest_md5':before['active'][src]}
            content = (json.dumps(updated,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
            encoded[src] = content
            hashes[src] = hashlib.md5(content).hexdigest()
            pending.remove(src); ready = True
        assert ready, 'Unresolved manifest parent'
    assert len(encoded) == 260 and audit.verify_unchanged(before) == current
    report = {'published':args.publish,'manifests':260,'current_sources':current,
        'published_md5':hashes if args.publish else {},'gpu_evidence':args.gpu_evidence,
        'native_preservation':native,'rebaked':False,'rgba_control_pairs':evidence['control_count'],
        'target_samples_excluded_from_equivalence':len(evidence['target_samples_not_equivalence_evidence']),
        'full_atlas_frame_proof':False,'payloads_unchanged':len(before['payloads'])}
    target = audit.OUT/('publication.json' if args.publish else 'publication_preflight.json')
    assert not target.exists()
    if args.publish:
        replaced = []
        try:
            for src,content in encoded.items():
                file = audit.path(src)
                staging = file.with_name(file.name+'.equipment-walk-incoming')
                assert not staging.exists()
                staging.write_bytes(content)
                os.replace(staging,file)
                replaced.append(src)
        except Exception:
            for src in replaced:
                file = audit.path(src)
                staging = file.with_name(file.name+'.equipment-walk-rollback')
                staging.write_bytes((audit.OUT/'manifest_before'/src[6:]).read_bytes())
                os.replace(staging,file)
            raise
        assert all(audit.digest(audit.path(src)) == value for src,value in hashes.items())
        assert all(audit.record(audit.path(src)) == info for src,info in before['payloads'].items())
        assert all(audit.record(audit.path(src)) == info['file'] for src,info in before['excluded'].items())
    audit.write_json(target,report)
    print('EQUIPMENT_WALK_ATLAS_PUBLICATION_PASS',args.publish,260)


if __name__ == '__main__':
    main()
