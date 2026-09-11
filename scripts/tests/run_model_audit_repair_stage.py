"""Hard timeout for the asset repair stage, retaining the complete output."""
import subprocess,sys
from pathlib import Path
from datetime import datetime
root=Path(__file__).resolve().parents[2]
sex=sys.argv[-1]
log=root/'.godot-temp/model_audit_repairs'/f'{sex}_{datetime.now():%Y%m%d_%H%M%S}.log'
rebuild='--rebuild' in sys.argv
script=root/('scripts/tests/rebuild_model_audit_candidate.py' if rebuild else 'scripts/tools/blender/run_model_audit_repairs.py')
timeout=480 if rebuild else 180
command=[str(root/'.tools/blender-4.2.22-windows-x64/blender.exe'),'--background','--python-exit-code','1','--python',str(script),'--',sex]
if '--finish-surfaces' in sys.argv:command.insert(-1,'--finish-surfaces')
if '--repair-faces' in sys.argv:command.insert(-1,'--repair-faces')
print('AUDIT_REPAIR_START',sex,f'timeout={timeout}s',log,flush=True)
with log.open('w',encoding='utf-8') as stream:
    result=subprocess.run(command,cwd=root,stdout=stream,stderr=subprocess.STDOUT,timeout=timeout)
print('AUDIT_REPAIR_EXIT',result.returncode,flush=True)
if result.returncode:print(log.read_text(encoding='utf-8')[-4000:])
sys.exit(result.returncode)
