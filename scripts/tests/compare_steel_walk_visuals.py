"""Exact regression evidence; visual fit is reviewed separately, never inferred."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
TASK=ROOT/'output/steel_mingguang_walk_20260919'


def pixels(path):
    return np.asarray(Image.open(path).convert('RGBA'))


def same_capture_source(capture, reference, editor_md5, candidate_sha256=None):
    for value in (capture, reference):
        assert value['status']=='CAPTURE_COMPLETE'
        assert value['editor_md5']==editor_md5
        assert isinstance(value.get('engine_version'),str) and value['engine_version']
    assert reference['engine_version']==capture['engine_version'], 'Cross-engine comparison'
    if candidate_sha256 is not None:
        assert reference['candidate_sha256']==candidate_sha256, 'Wrong candidate capture source'


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--revision',required=True)
    parser.add_argument('--baseline-phase',default='before')
    parser.add_argument('--low-baseline-phase',default='before_low')
    parser.add_argument('--reference-phase',default='candidate_v2')
    parser.add_argument('--formal',action='store_true',help='Compare imported formal captures with the reviewed raw candidate')
    args=parser.parse_args()
    assert args.revision.isalnum()
    assert all(p.replace('_','').isalnum() for p in (args.baseline_phase,args.low_baseline_phase,args.reference_phase))
    report={'revision':args.revision,'comparisons':{},'differences':[],
        'visual_clearance_acceptance':False,'meaning':'Regression only; main reviews fit and silhouette separately'}
    for sex in ('male','female'):
        build=json.loads((TASK/'combined'/args.revision/sex/'build.json').read_text())
        candidate=TASK/'combined'/args.revision/sex/f'standard_anime_{sex}_character_pack.glb'
        sha=hashlib.sha256(candidate.read_bytes()).hexdigest()
        assert sha==build['candidate_sha256']['.glb']
        if args.formal:
            formal=ROOT/'assets/characters/human/q35'/candidate.name
            assert hashlib.sha256(formal.read_bytes()).hexdigest()==sha
        for phase,count in [('candidate_',129),('candidate_low_',75)]:
            folder=TASK/((phase.replace('candidate_', 'formal_imported_') if args.formal else phase)+args.revision)/sex
            capture=json.loads((folder/'result.json').read_text())
            assert capture['status']=='CAPTURE_COMPLETE' and len(capture['images'])==count
            if args.formal:
                assert not capture['candidate_path'] and capture['model_sha256']==sha
                assert capture['model_load_mode']=='imported_resource', 'Raw GLB is not imported-resource evidence'
            else:
                assert capture['candidate_sha256']==sha
            assert capture['editor_md5']==hashlib.md5((ROOT/'scripts/ui/human_character_3d_editor.gd').read_bytes()).hexdigest()
            for resource in capture['images']:
                target=ROOT/resource.removeprefix('res://')
                assert target.is_file() and target.parent==folder
                if args.formal:
                    before=TASK/(phase+args.revision)/sex/target.name
                elif phase=='candidate_low_':
                    before=TASK/args.low_baseline_phase/sex/target.name
                elif target.name.startswith('mingguang_') and 'walk' not in target.name:
                    before=TASK/args.baseline_phase/sex/target.name
                elif not target.name.startswith('mingguang_'):
                    before=TASK/args.reference_phase/sex/target.name
                else:
                    continue
                label=sex+'/'+target.name
                before_capture=json.loads((before.parent/'result.json').read_text())
                same_capture_source(capture,before_capture,capture['editor_md5'],sha if args.formal else None)
                assert 'res://'+before.relative_to(ROOT).as_posix() in before_capture['images'], 'Unlisted reference image'
                if args.formal:
                    assert len(before_capture['images'])==count
                equal=np.array_equal(pixels(before),pixels(target))
                report['comparisons'][label]={'equal':equal,'before':str(before.relative_to(ROOT)),
                    'after':str(target.relative_to(ROOT))}
                if not equal: report['differences'].append(label)
    assert len(report['comparisons'])==(408 if args.formal else 348)
    report['status']='PIXEL_REGRESSION_PASS' if not report['differences'] else 'PIXEL_REGRESSION_FAIL'
    dest=TASK/'combined'/args.revision/('formal_imported_visual_regression.json' if args.formal else 'visual_regression.json')
    assert not dest.exists()
    dest.write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(report['status'],len(report['comparisons']),'pairs',report['differences'])
    assert not report['differences']


if __name__=='__main__':
    main()
