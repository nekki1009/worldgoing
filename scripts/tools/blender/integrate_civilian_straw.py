"""Append only the authored straw meshes; old GLB binary, bones and animation channels remain exact."""
from pathlib import Path
import copy,hashlib,json,shutil,sys
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).parent))
from medieval_cloth_export import append_cloth
sys.path.insert(0,str(ROOT/'scripts/tests'))
from validate_chinese_cloak_assets import read_glb
PREFIX=('Boots_Civilian_Straw_01_','Helmet_Civilian_Straw_01_')
def integrate(sex,baseline,root=ROOT,work=None):
    work=work or root/'assets/characters/human/q35/civilian_straw'
    source=baseline/f'standard_anime_{sex}_character_pack.glb';dest=work/f'candidate_{sex}.glb'
    append_cloth(source,work/f'subset_{sex}.glb',dest,{},PREFIX)
    old,raw=read_glb(source);new,added=read_glb(dest)
    assert added[:len(raw)]==raw
    for key in ['meshes','skins','animations','accessors','bufferViews','materials','images','textures','samplers']:
        assert new.get(key,[])[:len(old.get(key,[]))]==old.get(key,[]),key
    for i,node in enumerate(old['nodes']):
        a=copy.deepcopy(new['nodes'][i]);b=copy.deepcopy(node)
        assert a.get('children',[])[:len(b.get('children',[]))]==b.get('children',[])
        a.pop('children',None);b.pop('children',None);assert a==b, node.get('name')
    meta=json.loads((baseline/f'standard_anime_{sex}_character_pack.json').read_text(encoding='utf-8'))
    names=[x['name'] for x in new['nodes'][len(old['nodes']):] if 'mesh' in x]
    for slot,prefix in [('boots',PREFIX[0]),('helmet',PREFIX[1])]:meta['parts'][slot]+=[n for n in names if n.startswith(prefix)]
    meta['civilian_straw']={'version':1,'sex':sex,'new_parts':['boots_civilian_straw_01','helmet_civilian_straw_01'],'source':'assets/characters/human/q35/civilian_straw','old_binary_sha256':hashlib.sha256(raw).hexdigest(),'old_binary_prefix_exact':True}
    model=root/'assets/characters/human/q35'/f'standard_anime_{sex}_character_pack'
    shutil.copy2(dest,model.with_suffix('.glb'))
    model.with_suffix('.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    shutil.copy2(work/f'civilian_straw_{sex}.blend',model.with_suffix('.blend'))
    proof={'sex':sex,'baseline_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'candidate_sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'old_binary_prefix_exact':True,'old_meshes':len(old['meshes']),'old_skins':len(old['skins']),'old_animations':len(old['animations']),'old_nodes':len(old['nodes']),'old_arrays_and_existing_nodes_exact':True,'new_mesh_names':names}
    (work/f'native_diff_{sex}.json').write_text(json.dumps(proof,indent=2))
