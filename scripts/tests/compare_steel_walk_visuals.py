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


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--revision',required=True)
    args=parser.parse_args()
    assert args.revision.isalnum()
    report={'revision':args.revision,'comparisons':{},'differences':[],
        'visual_clearance_acceptance':False,'meaning':'Regression only; main reviews fit and silhouette separately'}
    for sex in ('male','female'):
        build=json.loads((TASK/'combined'/args.revision/sex/'build.json').read_text())
        candidate=TASK/'combined'/args.revision/sex/f'standard_anime_{sex}_character_pack.glb'
        sha=hashlib.sha256(candidate.read_bytes()).hexdigest()
        assert sha==build['candidate_sha256']['.glb']
        for phase,count in [('candidate_',129),('candidate_low_',75)]:
            folder=TASK/(phase+args.revision)/sex
            capture=json.loads((folder/'result.json').read_text())
            assert capture['status']=='CAPTURE_COMPLETE' and len(capture['images'])==count
            assert capture['candidate_sha256']==sha
            assert capture['editor_md5']==hashlib.md5((ROOT/'scripts/ui/human_character_3d_editor.gd').read_bytes()).hexdigest()
            for resource in capture['images']:
                target=ROOT/resource.removeprefix('res://')
                assert target.is_file() and target.parent==folder
                if phase=='candidate_low_':
                    before=TASK/'before_low'/sex/target.name
                elif target.name.startswith('mingguang_') and 'walk' not in target.name:
                    before=TASK/'before'/sex/target.name
                elif not target.name.startswith('mingguang_'):
                    before=TASK/'candidate_v2'/sex/target.name
                else:
                    continue
                label=sex+'/'+target.name
                equal=np.array_equal(pixels(before),pixels(target))
                report['comparisons'][label]={'equal':equal,'before':str(before.relative_to(ROOT)),
                    'after':str(target.relative_to(ROOT))}
                if not equal: report['differences'].append(label)
    assert len(report['comparisons'])==348
    report['status']='PIXEL_REGRESSION_PASS' if not report['differences'] else 'PIXEL_REGRESSION_FAIL'
    dest=TASK/'combined'/args.revision/'visual_regression.json'
    assert not dest.exists()
    dest.write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(report['status'],len(report['comparisons']),'pairs',report['differences'])
    assert not report['differences']


if __name__=='__main__':
    main()
