"""Bound each Blender stage and retain its full log without flooding the terminal."""
import argparse
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('--leather-helmet',action='store_true')
parser.add_argument('--lining',action='store_true')
parser.add_argument('--leather-boots',action='store_true')
parser.add_argument('--sex',choices=['male','female','both'],default='both')
parser.add_argument('stages',nargs='+',choices=['gray','preview','probe','detail','export'])
args=parser.parse_args()
logs=ROOT/'.godot-temp/chinese_equipment_runs'/datetime.now().strftime('%Y%m%d_%H%M%S')
logs.mkdir(parents=True,exist_ok=True)
for sex in ['male','female'] if args.sex=='both' else [args.sex]:
    for stage in args.stages:
        author='author_chinese_leather_boots.py' if args.leather_boots else 'author_chinese_lining.py' if args.lining else 'author_chinese_leather_helmet.py' if args.leather_helmet else 'author_chinese_leather_mingguang.py'
        command=[str(ROOT/'.tools/blender-4.2.22-windows-x64/blender.exe'),'--background','--python-exit-code','1','--python',str(ROOT/'scripts/tools/blender'/author),'--','--sex',sex,'--stage',stage]
        log=logs/f'{sex}_{stage}.log'
        print('START',sex,stage,'timeout=180s',flush=True)
        with log.open('w',encoding='utf-8') as stream:
            result=subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,timeout=180)
        print('RESULT',sex,stage,'EXIT='+str(result.returncode),'LOG='+str(log),flush=True)
        if result.returncode:sys.exit(result.returncode)
