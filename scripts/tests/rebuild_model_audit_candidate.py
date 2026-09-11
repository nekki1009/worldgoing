"""Exercise canonical builders with all outputs redirected away from live assets."""
import sys
from pathlib import Path
import bpy

root=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(root/'scripts/tools/blender'))
sex=sys.argv[-1]
if sex=='horse':import build_standard_horse_pack as api
elif sex=='female':import build_standard_anime_female_character_pack as api
else:import build_standard_anime_male_character_pack as api
dest=root/'assets/characters/human/q35/audit_repair/rebuild'
dest.mkdir(parents=True,exist_ok=True)
api.OUTPUT_DIR=str(dest)
api.OUTPUT_BLEND=str(dest/f'candidate_{sex}.blend')
api.OUTPUT_GLB=str(dest/f'candidate_{sex}.glb')
api.OUTPUT_METADATA=str(dest/f'candidate_{sex}.json')
api.PREVIEW_DIR=str(root/'.visual_captures/all_model_repaired/rebuild'/sex)
if sex=='horse':api.build_standard_horse_pack()
else:api.main()
bpy.ops.wm.quit_blender()
