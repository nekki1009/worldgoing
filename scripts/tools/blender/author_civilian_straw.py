"""Measured native-rig straw sandals and open conical hat. Build is explicit; export preserves edits."""
import argparse,hashlib,json,math,sys
from pathlib import Path
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).parent))
from author_chinese_leather_mingguang import Fitting,mesh_part,surface
from author_medieval_shoes import last
WORK=ROOT/'assets/characters/human/q35/civilian_straw'
PREFIX=('Boots_Civilian_Straw_01_','Helmet_Civilian_Straw_01_')

def mat(name,color):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*color,1)
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=.91
    return m

def tube(name,points,radius,material,fit,bone,weights=None):
    points=[Vector(p) for p in points];verts=[];faces=[];sides=6
    for i,p in enumerate(points):
        tangent=(points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized()
        normal=tangent.cross(Vector((0,0,1)))
        if normal.length<.001:normal=tangent.cross(Vector((0,1,0)))
        normal.normalize();binormal=tangent.cross(normal).normalized()
        for k in range(sides):verts.append(p+radius*(normal*math.cos(k*math.tau/sides)+binormal*math.sin(k*math.tau/sides)))
    for i in range(len(points)-1):
        for k in range(sides):faces.append((i*sides+k,i*sides+(k+1)%sides,(i+1)*sides+(k+1)%sides,(i+1)*sides+k))
    return mesh_part(name,verts,faces,material,fit,bone,weights)

def tag(parts):
    for p in parts:
        p['part_slot']='boots' if p.name.startswith(PREFIX[0]) else 'helmet'
        p['part_id']='boots_civilian_straw_01' if p.name.startswith(PREFIX[0]) else 'helmet_civilian_straw_01'
        p['civilian_straw_revision']=1

def build(fit):
    straw=mat('CivilianStraw_Fibre',(.24,.15,.055));dark=mat('CivilianStraw_Weft',(.15,.09,.03));edge=mat('CivilianStraw_Edge',(.36,.23,.10));band=mat('CivilianStraw_Band',(.22,.29,.35))
    parts=[];measure={}
    for side,sign in [('L',1),('R',-1)]:
        foot=fit.bone('J_Bip_'+side+'_Foot');rings,outline,low=last(fit,side,sign,foot.z+.012)
        front=min(p.y for p in outline);back=max(p.y for p in outline)
        left=min(p.x for p in outline);right=max(p.x for p in outline)
        prefix=PREFIX[0];n=len(outline)
        verts=[Vector((p.x,p.y,z)) for z in [low-.010,low+.001] for p in outline]
        faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        parts.append(mesh_part(prefix+'WovenSole_'+side,verts,faces,straw,fit,'J_Bip_'+side+'_Foot',fit.weights))
        for j,fraction in enumerate([.18,.34,.50]):
            y=front+(back-front)*fraction;pts=[]
            for k in range(21):
                x=left+(right-left)*k/20
                hit,_,_,_=fit.bvh.ray_cast(Vector((x,y,foot.z+.16)),Vector((0,0,-1)),.5)
                z=hit.z+.005 if hit is not None else low+.006
                pts.append(Vector((x,y,z)))
            parts.append(tube(prefix+'PlaitedStrap%d_'%j+side,pts,.0045,band if j==2 else edge,fit,'J_Bip_'+side+'_Foot',fit.weights))
        heel=[Vector((left,back-.018,low+.028)),Vector((foot.x,back+.003,low+.037)),Vector((right,back-.018,low+.028))]
        parts.append(tube(prefix+'SoleBinding_'+side,[Vector((p.x,p.y,low-.002)) for p in outline+[outline[0]]],.0025,edge,fit,'J_Bip_'+side+'_Foot',fit.weights))
        measure[side]={'bone':list(foot),'foot_low':low,'footprint':[left,right,front,back]}
    head=fit.bone('J_Bip_C_Head')
    scalp=[p for p in fit.points if p.z>head.z+.08]
    for obj in bpy.data.objects:
        if obj.type=='MESH' and obj.name.startswith('Face_Standard_01'):
            scalp += [obj.matrix_world@v.co for v in obj.data.vertices if (obj.matrix_world@v.co).z>head.z+.08]
    rx=max(.255,max(abs(p.x-head.x) for p in scalp)*1.85)
    cy=(min(p.y for p in scalp)+max(p.y for p in scalp))/2
    ry=max(.255,(max(p.y for p in scalp)-min(p.y for p in scalp))*.96)
    brim=head.z+.115;peak=max(p.z for p in scalp)+.075
    def crown(u,v):
        a=u*math.tau;r=.004+(1-.004)*v
        return Vector((head.x+rx*r*math.sin(a),cy-ry*r*math.cos(a),brim+(peak-brim)*(1-r**1.5)-.008*math.cos(a)*r*r))
    parts.append(surface(PREFIX[1]+'Crown',crown,16,96,straw,fit,'J_Bip_C_Head',thickness=.004))
    parts.append(tube(PREFIX[1]+'BoundBrim',[crown(k/128,1) for k in range(129)],.004,edge,fit,'J_Bip_C_Head'))
    # The visible underside opening stays above the forehead; no chin cord crosses the face.
    parts.append(tube(PREFIX[1]+'InnerBand',[Vector((head.x+.119*math.sin(k*math.tau/64),cy-.135*math.cos(k*math.tau/64),brim+.003)) for k in range(65)],.004,band,fit,'J_Bip_C_Head'))
    measure['head']={'bone':list(head),'brim_z':brim,'peak_z':peak,'radius':[rx,ry],'center_y':cy}
    tag(parts);return parts,measure,crown

def detail(fit,measure):
    straw=bpy.data.materials['CivilianStraw_Fibre'];dark=bpy.data.materials['CivilianStraw_Weft'];edge=bpy.data.materials['CivilianStraw_Edge'];h=measure['head'];head=Vector(h['bone']);rx,ry=h['radius'];cy=h['center_y']
    def crown(u,v,lift=.0015):
        a=u*math.tau;r=.004+(1-.004)*v
        return Vector((head.x+rx*r*math.sin(a),cy-ry*r*math.cos(a),h['brim_z']+(h['peak_z']-h['brim_z'])*(1-r**1.5)-.008*math.cos(a)*r*r+lift))
    made=[]
    for ring in range(1,29):
        r=ring/29
        made.append(tube(PREFIX[1]+'WovenRing_%02d'%ring,[crown(k/96,r,.0015+.0006*math.sin(k*math.pi/3)) for k in range(97)],.0011,edge if ring%3 else dark,fit,'J_Bip_C_Head'))
    for rib in range(48):
        made.append(tube(PREFIX[1]+'RadialWeft_%02d'%rib,[crown(rib/48,j/20) for j in range(21)],.0011,straw if rib%3 else dark,fit,'J_Bip_C_Head'))
    for side in ['L','R']:
        m=measure[side];left,right,front,back=m['footprint'];low=m['foot_low']
        _,outline,_=last(fit,side,1 if side=='L' else -1,Vector(m['bone']).z+.012)
        for j in range(1,18):
            y=front+(back-front)*j/18;pts=[]
            # Exposed sole ends carry real transverse straw fibres, never painted leather.
            crossings=[]
            for a,b in zip(outline,outline[1:]+outline[:1]):
                if (a.y<=y<b.y) or (b.y<=y<a.y):crossings.append(a.x+(b.x-a.x)*(y-a.y)/(b.y-a.y))
            if len(crossings)<2:continue
            lo,hi=min(crossings)+.002,max(crossings)-.002
            for k in range(9):pts.append(Vector((lo+(hi-lo)*k/8,y,low+.002)))
            made.append(tube(PREFIX[0]+'SoleWeft_%02d_'%j+side,pts,.0012,edge,fit,'J_Bip_'+side+'_Foot',fit.weights))
    tag(made);return made


def fit_female_footbeds(fit,measure):
    # Female native feet have raised heels: a flat plate leaves an air gap.
    # Keep the original feet and curve only the new sandals to their underside.
    from bisect import bisect_right
    for side in ['L','R']:
        m=measure[side];left,right,front,back=m['footprint'];low=m['foot_low'];cx=m['bone'][0]
        samples=[]
        for j in range(49):
            y=front+(back-front)*j/48;hits=[]
            for dx in [-.012,-.006,0,.006,.012]:
                hit,_,_,_=fit.bvh.ray_cast(Vector((cx+dx,y,low-.10)),Vector((0,0,1)),.30)
                if hit is not None:hits.append(hit.z)
            if hits:samples.append((y,min(hits)))
        assert len(samples)>24,(side,'insufficient plantar samples')
        raw_samples=samples[:]
        heel=min(z for y,z in samples if .65<(y-front)/(back-front)<.88)
        toe=min(z for y,z in samples if (y-front)/(back-front)<.35)
        filtered=[];last_z=toe
        for j,(y,z) in enumerate(samples):
            window=[(samples[k][1],5-abs(k-j)) for k in range(max(0,j-4),min(len(samples),j+5))]
            smooth=sum(z*w for z,w in window)/sum(w for _,w in window)
            if (y-front)/(back-front)<.28:smooth=toe
            last_z=min(heel,max(last_z,smooth))
            filtered.append((y,last_z))
        samples=filtered;ys=[p[0] for p in samples]
        def offset(y):
            i=max(1,min(len(samples)-1,bisect_right(ys,y)))
            a,b=samples[i-1],samples[i];t=max(0,min(1,(y-a[0])/(b[0]-a[0])))
            return max(0,a[1]+(b[1]-a[1])*t-low-.0005)
        for obj in bpy.data.objects:
            if not obj.name.startswith(PREFIX[0]) or not obj.name.endswith('_'+side):continue
            for vertex in obj.data.vertices:
                p=vertex.co
                if 'PlaitedStrap' not in obj.name:p.z+=offset(p.y)
                elif p.z<low+.018:p.z+=offset(p.y)*max(0,min(1,(low+.018-p.z)/.012))
        m['plantar_samples_y_z']=[list(p) for p in raw_samples]
        m['smoothed_footbed_y_z']=[list(p) for p in samples]
        m['footbed_heel_contact_z']=heel
        m['heel_lift_from_low']=offset(back-.012)

def reset(arm):
    if arm.animation_data:arm.animation_data.action=None
    for track in arm.animation_data.nla_tracks if arm.animation_data else []:track.mute=True
    for bone in arm.pose.bones:bone.matrix_basis.identity()
    bpy.context.scene.frame_set(0);bpy.context.view_layer.update()

def export(fit,sex):
    from integrate_civilian_straw import integrate
    parts=[o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith(PREFIX)]
    reset(fit.arm);bpy.ops.object.select_all(action='DESELECT')
    for p in [fit.arm]+parts:p.hide_set(False);p.hide_viewport=False;p.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(WORK/f'subset_{sex}.glb'),export_format='GLB',use_selection=True,export_animations=False,export_skins=True,export_morph=False,export_apply=False)
    integrate(sex,args.baseline,ROOT,WORK)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--sex',choices=['male','female'],required=True);parser.add_argument('--stage',choices=['build','detail','repair','export'],required=True);parser.add_argument('--baseline',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);WORK.mkdir(parents=True,exist_ok=True);bpy.context.preferences.filepaths.save_version=0
    source=args.baseline/f'standard_anime_{args.sex}_character_pack.blend' if args.stage=='build' else WORK/f'civilian_straw_{args.sex}.blend'
    bpy.ops.wm.open_mainfile(filepath=str(source));arm=bpy.data.objects['Armature'];reset(arm);fit=Fitting(arm,args.sex)
    if args.stage=='build':
        assert not any(o.name.startswith(PREFIX) for o in bpy.data.objects)
        parts,measure,_=build(fit);(WORK/f'measure_{args.sex}.json').write_text(json.dumps(measure,indent=2))
    elif args.stage=='detail':
        assert not any(o.name.startswith(PREFIX[1]+'WovenRing_') for o in bpy.data.objects),'Do not overwrite authored details'
        for o in list(bpy.data.objects):
            if o.name.startswith(PREFIX):bpy.data.objects.remove(o,do_unlink=True)
        parts,measure,_=build(fit)
        (WORK/f'measure_{args.sex}.json').write_text(json.dumps(measure,indent=2))
        detail(fit,measure)
    if args.sex=='female' and args.stage in ['build','detail']:
        fit_female_footbeds(fit,measure)
        (WORK/f'measure_{args.sex}.json').write_text(json.dumps(measure,indent=2))
    # Rigid soles and their cordwork follow their own foot only. Nearest-body
    # weights below the feet can sample the opposite foot and stretch during gait.
    if args.stage!='export':
        for obj in bpy.data.objects:
            if obj.type=='MESH' and obj.name.startswith(PREFIX[0]):
                side=obj.name.rsplit('_',1)[-1];assert side in ['L','R']
                obj.vertex_groups.clear()
                group=obj.vertex_groups.new(name='J_Bip_'+side+'_Foot')
                group.add(list(range(len(obj.data.vertices))),1.0,'REPLACE')
    if args.stage!='export':bpy.ops.wm.save_as_mainfile(filepath=str(WORK/f'civilian_straw_{args.sex}.blend'),compress=True)
    export(fit,args.sex)
    print('CIVILIAN_STRAW_READY',args.sex,args.stage,flush=True)
