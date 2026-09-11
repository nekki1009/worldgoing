"""Publish only after asset checks and an unchanged live-baseline guard."""
import hashlib,json,shutil
from pathlib import Path
import validate_chinese_leather_boots as validated
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'.godot-temp/chinese_leather_boots_baseline_20260910'
WORK=ROOT/'assets/characters/human/q35/chinese_leather_boots'
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
copies=[]
for sex in ['male','female']:
    for ext in ['blend','glb','json']:
        name=f'standard_anime_{sex}_character_pack.{ext}'
        target=WORK.parent/name
        assert digest(target)==digest(BASE/name),'Live pack changed since boots baseline: '+name
        source=WORK/f'chinese_leather_boots_{sex}.blend' if ext=='blend' else WORK/f'candidate_{sex}.{ext}'
        assert source.is_file() and source.stat().st_size>0
        copies.append((source,target))
report=[]
for source,target in copies:
    shutil.copy2(source,target);assert digest(source)==digest(target)
    report.append({'source':str(source),'target':str(target),'sha256':digest(target)})
(WORK/'publication.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('CHINESE_LEATHER_BOOTS_PUBLISHED',len(copies))
