import json
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]/'output/weapon_refresh_20260913'
for stage in ['baseline','candidate_gray','candidate_guard']:
    path = ROOT/stage/'male_measurements.json'
    if not path.exists():
        continue
    rows = json.loads(path.read_text())
    for clip in ['attack_spear','attack_axe']:
        selected = [row for row in rows if row['clip'] == clip]
        def angles(values):
            values = np.array(values)
            values /= np.linalg.norm(values,axis=1)[:,None]
            return np.degrees(np.arccos(np.clip(values@values[0],-1,1))).round(3).tolist()
        print(stage,clip,'shield',angles([row['shield_front'] for row in selected]))
        if clip == 'attack_spear':
            print('spear',angles([np.array(row['shaft_b'])-row['shaft_a'] for row in selected]))
