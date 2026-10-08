"""Positive source binding and rejection cases; never launches or publishes assets."""
import copy
import json
from compare_steel_walk_visuals import TASK, same_capture_source


def main():
    rejected = []
    for sex in ('male', 'female'):
        candidate = json.loads((TASK/'candidate_v5'/sex/'result.json').read_text())
        formal = json.loads((TASK/'formal_v5'/sex/'result.json').read_text())
        sha = json.loads((TASK/'combined/v5'/sex/'build.json').read_text())['candidate_sha256']['.glb']
        same_capture_source(formal, candidate, formal['editor_md5'], sha)
        for key, value in [('candidate_sha256', 'wrong'), ('engine_version', 'wrong'),
                           ('status', 'INCOMPLETE'), ('editor_md5', 'wrong')]:
            altered = copy.deepcopy(candidate)
            altered[key] = value
            try:
                same_capture_source(formal, altered, formal['editor_md5'], sha)
            except (AssertionError, KeyError):
                rejected.append(sex+'/'+key)
            else:
                raise AssertionError('Source corruption accepted: '+key)
        for missing in (False, True):
            pair = [copy.deepcopy(formal), copy.deepcopy(candidate)]
            for capture in pair:
                if missing:
                    capture.pop('engine_version')
                else:
                    capture['engine_version'] = ''
            try:
                same_capture_source(*pair, formal['editor_md5'], sha)
            except (AssertionError, KeyError):
                rejected.append(sex+'/missing_engine' if missing else sex+'/empty_engine')
            else:
                raise AssertionError('Missing engine identity accepted')
    assert len(rejected) == 12
    print('STEEL_WALK_CAPTURE_SOURCE_GUARDS_PASS 2 actual positive pairs; 12 corruption rejections')


if __name__ == '__main__':
    main()
