"""Bounded CPU Blender job with retained, uniquely named logs."""
import argparse
import datetime
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--sex', choices=('male', 'female'), required=True)
    parser.add_argument('--stage', choices=('inspect', 'author', 'export', 'check', 'loader-check', 'refine-arms'), required=True)
    parser.add_argument('--timeout', type=int, default=300)
    args = parser.parse_args()
    out = ROOT / 'output/equipment_matrix_20260918/mounted/runs' / (datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f') + '_' + args.sex + '_' + args.stage)
    out.mkdir(parents=True)
    resources = ROOT / '.godot-temp/mounted_blender_resources'
    resources.mkdir(parents=True, exist_ok=True)
    command = [str(ROOT / '.tools/blender-4.2.22-windows-x64/blender.exe'), '--background', '--threads', '2', '--python-exit-code', '1',
               '--python', str(ROOT / 'scripts/tools/blender/author_mounted_heavy.py'), '--', '--sex', args.sex, '--stage', args.stage]
    result = {'command': command, 'timeout_seconds': args.timeout}
    started = datetime.datetime.now()
    with (out / 'stdout.log').open('w', encoding='utf-8') as log, (out / 'stderr.log').open('w', encoding='utf-8') as err:
        try:
            run = subprocess.run(command, cwd=ROOT, env={**os.environ, 'BLENDER_USER_RESOURCES': str(resources)},
                                 stdout=log, stderr=err, timeout=args.timeout)
            result['exit_code'] = run.returncode
        except subprocess.TimeoutExpired:
            result['exit_code'] = 124
            result['timeout'] = True
    result['elapsed_seconds'] = (datetime.datetime.now() - started).total_seconds()
    result['status'] = 'PASS' if result['exit_code'] == 0 else 'FAIL'
    (out / 'result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({'run': str(out), **result}, indent=2), flush=True)
    sys.exit(result['exit_code'])
