"""Move only formal cloth metadata to armor; retain the exact model binaries."""
import copy
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/medieval_cloth_armor_20260916'
backup = OUT / 'baseline'
backup.mkdir(parents=True, exist_ok=True)
for sex in ['male', 'female']:
    path = ROOT / f'assets/characters/human/q35/standard_anime_{sex}_character_pack.json'
    saved = backup / path.name
    if not saved.exists():
        shutil.copy2(path, saved)
    old = json.loads(saved.read_text(encoding='utf-8'))
    new = copy.deepcopy(old)
    cloth = [name for name in old['parts']['outfit'] if name.startswith('Outfit_Medieval_')]
    assert len(cloth) == (31 if sex == 'male' else 28)
    assert not any(name in new['parts']['armor'] for name in cloth)
    new['parts']['outfit'] = [name for name in old['parts']['outfit'] if name not in cloth]
    new['parts']['armor'].extend(cloth)
    new['medieval_cloth'].update(slot='armor', category='cloth')
    current = json.loads(path.read_text(encoding='utf-8'))
    assert current in [old, new], 'Formal metadata changed outside this reclassification'
    path.write_text(json.dumps(new, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
    assert json.loads(path.read_text(encoding='utf-8')) == new
    for ext in ['blend', 'glb']:
        formal = path.with_suffix('.'+ext)
        baseline = ROOT / 'output/medieval_cloth_fit_20260916/baseline' / formal.name
        def md5(file):
            with file.open('rb') as stream:
                return hashlib.file_digest(stream, 'md5').hexdigest()
        assert md5(formal) == md5(baseline), f'Model bytes changed: {formal}'
    print('CLOTH_ARMOR_METADATA_PASS', sex, len(cloth), 'original underwear/model/rig preserved')
