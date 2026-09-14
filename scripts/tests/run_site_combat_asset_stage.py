"""Run one character-authoring stage with a hard deadline and a retained log."""
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

root = Path(__file__).resolve().parents[2]
stage, sex = sys.argv[1:3]
weapon_stage = stage in ['weapon_gray', 'weapon_final', 'weapon_keep_old']
western_stage = stage.startswith('western_')
work = root / ('.godot-temp/weapon_refresh_20260913' if weapon_stage else '.godot-temp/mingguang_low_pose_20260912' if stage == 'mingguang' else '.godot-temp/site_combat_assets')
if western_stage:
    work = root / '.godot-temp/western_plate_20260913'
if stage in ['crossbow_stance', 'crossbow_stance_audit']:
    work = root / '.godot-temp/crossbow_stance_20260914'
work.mkdir(parents=True, exist_ok=True)
log = work / f'{stage}_{sex}_{datetime.now():%Y%m%d_%H%M%S}.log'
environment = os.environ.copy()
environment['BLENDER_USER_RESOURCES'] = str(root / '.godot-temp/blender-user-resources')
script = 'author_weapon_refresh.py' if weapon_stage else 'author_mingguang_low_pose.py' if stage == 'mingguang' else 'author_site_combat_character.py'
arguments = [sex, stage.removeprefix('weapon_')] if weapon_stage else [sex] if stage == 'mingguang' else [stage, sex]
if western_stage:
    script, arguments = 'author_western_plate.py', [sex, stage.removeprefix('western_')]
if stage in ['crossbow_stance', 'crossbow_stance_audit']:
    script, arguments = 'fix_crossbow_idle_stance.py', [sex] + (['--audit-source'] if stage.endswith('_audit') else [])
command = [str(root / '.tools/blender-4.2.22-windows-x64/blender.exe'), '--background',
           '--python-exit-code', '1', '--python',
           str(root / 'scripts/tools/blender' / script), '--', *arguments]
print('SITE_COMBAT_ASSET_START', stage, sex, 'deadline=180s', log, flush=True)
with log.open('w', encoding='utf-8') as stream:
    try:
        result = subprocess.run(command, cwd=root, env=environment, stdout=stream,
                                stderr=subprocess.STDOUT, timeout=180)
        code = result.returncode
    except subprocess.TimeoutExpired:
        code = 124
print(log.read_text(encoding='utf-8', errors='replace')[-5000:])
print('SITE_COMBAT_ASSET_EXIT', code, flush=True)
sys.exit(code)
