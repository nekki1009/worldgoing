"""Hard-bounded Blender worker; retain each attempt log, including failures."""
import argparse
import subprocess
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--sex', choices=('male', 'female', 'both'), default='both')
parser.add_argument('--timeout', type=int, default=240)
parser.add_argument('stage', choices=('inspect', 'build', 'export', 'test', 'preview', 'fit-skirt'))
parser.add_argument('--gpu-granted', action='store_true')
args = parser.parse_args()
logs = ROOT / 'reports/output/equipment_matrix_20260918/armor/logs' / datetime.now().strftime('%Y%m%d_%H%M%S')
logs.mkdir(parents=True, exist_ok=True)
for sex in ('male', 'female') if args.sex == 'both' else (args.sex,):
    command = [str(ROOT / '.tools/blender-4.2.22-windows-x64/blender.exe'),
               '--background', '--python-exit-code', '1', '--python',
               str(ROOT / 'scripts/tools/blender/author_cultural_armor.py'),
               '--', '--sex', sex, '--stage', args.stage]
    if args.gpu_granted:
        command.append('--gpu-granted')
    log = logs / f'{sex}_{args.stage}.log'
    print('START', sex, args.stage, 'timeout', args.timeout, 'LOG', log, flush=True)
    try:
        with log.open('w', encoding='utf-8') as stream:
            result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=args.timeout)
    except subprocess.TimeoutExpired:
        print('TIMEOUT', sex, args.stage, flush=True)
        raise
    print('EXIT', result.returncode, sex, args.stage, flush=True)
    if result.returncode:
        raise SystemExit(result.returncode)
