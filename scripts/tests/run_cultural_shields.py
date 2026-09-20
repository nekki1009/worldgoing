"""Run only shield stages, each with a hard process timeout and retained log."""
import argparse
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--sex', choices=['male', 'female', 'both'], default='both')
parser.add_argument('--timeout', type=int, default=180)
parser.add_argument('stages', nargs='+', choices=['probe', 'build', 'holster', 'carry_probe', 'rigid_carry', 'export', 'test', 'preview', 'back_preview'])
args = parser.parse_args()
logs = ROOT / 'reports/output/equipment_matrix_20260918/shields/logs' / datetime.now().strftime('%Y%m%d_%H%M%S')
logs.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, BLENDER_USER_RESOURCES=str(ROOT / '.godot-temp/blender-user-resources'))
for sex in ['male', 'female'] if args.sex == 'both' else [args.sex]:
    for stage in args.stages:
        log = logs / f'{sex}_{stage}.log'
        command = [str(ROOT / '.tools/blender-4.2.22-windows-x64/blender.exe'),
                   '--background', '--python-exit-code', '1', '--python',
                   str(ROOT / 'scripts/tools/blender/author_cultural_shields.py'),
                   '--', '--sex', sex, '--stage', stage]
        print('START', sex, stage, f'timeout={args.timeout}s', flush=True)
        with log.open('w', encoding='utf-8') as stream:
            try:
                result = subprocess.run(command, cwd=ROOT, env=env, stdout=stream,
                                        stderr=subprocess.STDOUT, timeout=args.timeout)
            except subprocess.TimeoutExpired:
                print('TIMEOUT', str(log), flush=True)
                sys.exit(124)
        print('RESULT', sex, stage, 'exit=' + str(result.returncode), str(log), flush=True)
        if result.returncode:
            sys.exit(result.returncode)
