"""Preserve existing atlas admission only after native bytes + exact GPU proof.

Does not bake/admit hats or edit any page, collision, pose, dye mask or reader.
Already stale catalogs remain stale. Any unrelated dependency drift aborts.
"""
import copy
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/cloth_hats_20260918'
if '--neutral-faces' in sys.argv: OUT=ROOT/'output/neutral_faces_20260918'
BACK=OUT/'atlas_before'
ALLOWED={f'res://assets/characters/human/q35/standard_anime_{sex}_character_pack.glb' for sex in ('male','female')}|{'res://scripts/ui/human_character_3d_editor.gd','res://scripts/ui/equipment_dye.gd'}
STAMP='cloth_hats_additive_revalidation'
if '--neutral-faces' in sys.argv: STAMP='neutral_faces_additive_revalidation'


def path(resource):
    assert resource.startswith('res://')
    target=(ROOT/resource[6:]).resolve()
    assert target.is_relative_to(ROOT.resolve())
    return target


def md5(file):
    with file.open('rb') as stream:return hashlib.file_digest(stream,'md5').hexdigest()


def main():
    if '--snapshot' in sys.argv:
        assert not (OUT/'atlas_snapshot.json').exists()
        active={};stale=[];sources={}
        files=list((ROOT/'assets/characters/terrain_lab_army').rglob('*.json'))+[ROOT/'assets/vehicles/logistics/v1/riders/manifest.json']
        for file in files:
            value=json.loads(file.read_text(encoding='utf-8-sig'))
            if not value.get('source_fingerprints'):continue
            resource='res://'+file.relative_to(ROOT).as_posix()
            ok=True
            for src,expected in value['source_fingerprints'].items():
                if src not in sources:
                    original=OUT/'baseline'/(path(src).name+('.txt' if src.endswith('.gd') else ''))
                    sources[src]=md5(original if src in ALLOWED else path(src))
                current=sources[src]
                ok &= current==expected
            if value.get('source_manifest'):ok &= md5(path(value['source_manifest']))==value['source_manifest_md5']
            if not ok:stale.append(resource);continue
            target=BACK/file.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(file,target);active[resource]=md5(file)
        assert len(active)>=93,len(active)
        (OUT/'atlas_snapshot.json').write_text(json.dumps({'active':active,'stale':stale,'sources':sources},indent=2))
        print('CLOTH_HATS_ATLAS_SNAPSHOT',len(active),'active;',len(stale),'already stale')
        return
    snapshot=json.loads((OUT/'atlas_snapshot.json').read_text())
    current={src:md5(path(src)) for src in snapshot['sources']}
    for src,before in snapshot['sources'].items():
        assert src in ALLOWED or before==current[src],'Unrelated source drift: '+src
    contract=json.loads((OUT/'formal_contract.json').read_text())
    old_dye=(OUT/'baseline/equipment_dye.gd.txt').read_text(encoding='utf-8')
    expected_dye=old_dye.replace('"ChineseGear_Horsehair4"],','"ChineseGear_Horsehair4", "ClothHats_Fabric", "ClothHats_Band", "ClothHats_Seams"],')
    assert expected_dye==path('res://scripts/ui/equipment_dye.gd').read_text(encoding='utf-8'),'Only the three additive cloth material names may change dye policy'
    for row in contract:
        sex=row['sex']
        with path(f'res://assets/characters/human/q35/standard_anime_{sex}_character_pack.glb').open('rb') as stream:
            assert hashlib.file_digest(stream,'sha256').hexdigest()==row['sha256']['glb']
        before=json.loads((OUT/f'regression/before_fixed/{sex}/result.json').read_text())
        after=json.loads((OUT/f'regression/after_fixed/{sex}/result.json').read_text())
        assert before['samples']==after['samples'] and len(after['samples'])>=120
        assert before['editor_md5']==snapshot['sources']['res://scripts/ui/human_character_3d_editor.gd']
        assert before['glb_md5']==snapshot['sources'][f'res://assets/characters/human/q35/standard_anime_{sex}_character_pack.glb']
        assert after['editor_md5']==current['res://scripts/ui/human_character_3d_editor.gd']
        assert after['dye_md5']==current['res://scripts/ui/equipment_dye.gd']
        assert after['glb_md5']==current[f'res://assets/characters/human/q35/standard_anime_{sex}_character_pack.glb']
    pending=dict(snapshot['active']);encoded={};hashes={}
    while pending:
        progress=False
        for resource,old_hash in list(pending.items()):
            original=json.loads((BACK/resource[6:]).read_text(encoding='utf-8-sig'))
            parent=original.get('source_manifest')
            # The equipment catalog deliberately stores only the parent's hash.
            # Resolve that existing implicit dependency before hashing children.
            if not parent and 'source_manifest_md5' in original:
                assert resource.endswith('/standard_soldier/recipes/v1/catalog.json')
                parent='res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json'
            if parent in pending:continue
            updated=copy.deepcopy(original)
            updated['source_fingerprints']={src:current[src] for src in original['source_fingerprints']}
            if parent:updated['source_manifest_md5']=hashes[parent] if parent in hashes else md5(path(parent))
            updated[STAMP]={'rebaked':False,'evidence':OUT.relative_to(ROOT).as_posix(),'old_manifest_md5':old_hash,'old_sources':{src:snapshot['sources'][src] for src in sorted(ALLOWED)}}
            content=(json.dumps(updated,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
            encoded[resource]=content;hashes[resource]=hashlib.md5(content).hexdigest()
            pending.pop(resource);progress=True
        assert progress,'Manifest dependency cycle'
    if '--publish' in sys.argv:
        previous=json.loads((OUT/'atlas_revalidation.json').read_text()) if (OUT/'atlas_revalidation.json').exists() else None
        expected_hashes={**snapshot['active'],**(previous['published_md5'] if previous else {})}
        for resource in encoded:assert md5(path(resource))==expected_hashes[resource],'Concurrent atlas change: '+resource
        for src,value in current.items():assert md5(path(src))==value,'Concurrent dependency change'
        # Preflight all before replacing, preserving exact backups for recovery.
        replaced=[];prior={resource:path(resource).read_bytes() for resource in encoded}
        try:
            for resource,content in encoded.items():
                target=path(resource)
                assert md5(target)==expected_hashes[resource]
                tmp=target.with_suffix('.cloth-hats-incoming')
                assert not tmp.exists()
                tmp.write_bytes(content);os.replace(tmp,target);replaced.append(resource)
        except Exception:
            for resource in replaced:path(resource).write_bytes(prior[resource])
            raise
    for resource,content in encoded.items():assert path(resource).read_bytes()==content,resource
    comparisons=sum(len(json.loads((OUT/f'regression/after_fixed/{sex}/result.json').read_text())['samples']) for sex in ('male','female'))
    (OUT/'atlas_revalidation.json').write_text(json.dumps({'manifests':len(encoded),'unchanged_stale':snapshot['stale'],'current_sources':current,'published_md5':hashes,'rebaked':False,'rgba_comparisons':comparisons},indent=2))
    print('ADDITIVE_ATLAS_PROVENANCE_PASS',len(encoded),'manifests;',comparisons,'identical RGBA images; unchanged native assets; no admission relaxation')


if __name__=='__main__':main()
