"""Editable geometric trims, embossed leather and sculpted fittings for the pair.

Only invoked by the explicit detail stage; export does not recreate this art.
"""
import math
import bpy
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree
from author_chinese_leather_mingguang import ARMOR, HELMET, WORK, material, mesh_part


def leather_texture():
    size=1024
    rng=np.random.default_rng(31092026)
    y,x=np.mgrid[0:size,0:size]/size
    grain=rng.normal(0,1,(size,size))
    # Shallow interlocking pores with broader uneven tanning, not painted noise alone.
    pores=np.sin(x*1230+np.sin(y*941))*np.sin(y*1080+np.sin(x*870))
    tone=.055*np.sin(x*31+y*8)+.032*np.sin(y*83-x*43)+.032*grain+.022*pores
    border=np.minimum.reduce([x,1-x,y,1-y])
    worn=np.exp(-((border-.022)/.012)**2)*.16
    # Generated image values are written directly into sRGB PNG channels.
    base=np.array([.30,.165,.085])[None,None,:]
    rgb=np.clip(base*(1+tone[:,:,None])+worn[:,:,None]*np.array([.34,.17,.066]),0,1)
    height=.013*pores+.007*grain
    # Debossed symmetrical cloud tendrils use the UV surface, visible at close range.
    motif=np.ones_like(x)*9
    for cx,cy,scale in [(cx,cy,.083) for cx in [.19,.5,.81] for cy in [.23,.5,.77]]:
        for t in np.linspace(0,math.tau,65):
            px=cx+scale*(math.cos(t)+.22*math.cos(3*t))
            py=cy+scale*(.65*math.sin(t)+.18*math.sin(2*t))
            motif=np.minimum(motif,(x-px)**2+(y-py)**2)
    embossed=np.exp(-motif/.000015)
    rgb*=1-embossed[:,:,None]*.23
    height-=embossed*.10
    gy,gx=np.gradient(height)
    normal=np.stack([-gx*22,gy*22,np.ones_like(x)],axis=2)
    normal/=np.linalg.norm(normal,axis=2,keepdims=True)
    maps={'LeatherColor':rgb,'LeatherNormal':normal*.5+.5,'LeatherRoughness':np.repeat(np.clip(.70+.08*grain-.12*worn,.48,.91)[:,:,None],3,axis=2)}
    images={}
    for name,values in maps.items():
        img=bpy.data.images.new('ChineseGear_'+name,width=size,height=size)
        img.colorspace_settings.name='sRGB' if name.endswith('Color') else 'Non-Color'
        rgba=np.concatenate([values,np.ones((size,size,1))],axis=2).astype(np.float32)
        img.pixels.foreach_set(rgba.ravel())
        img.filepath_raw=str(WORK/(name+'.png')); img.file_format='PNG'; img.save();img.pack()
        images[name]=img
    mat=material('Leather',(.10,.045,.022),roughness=.72)
    nodes=mat.node_tree.nodes;links=mat.node_tree.links;bsdf=nodes.get('Principled BSDF')
    for name,target in [('LeatherColor','Base Color'),('LeatherRoughness','Roughness')]:
        tex=nodes.new('ShaderNodeTexImage');tex.image=images[name]
        links.new(tex.outputs['Color'],bsdf.inputs[target])
    tex=nodes.new('ShaderNodeTexImage');tex.image=images['LeatherNormal']
    normal_node=nodes.new('ShaderNodeNormalMap');normal_node.inputs['Strength'].default_value=.34
    links.new(tex.outputs['Color'],normal_node.inputs['Color']);links.new(normal_node.outputs['Normal'],bsdf.inputs['Normal'])


class Detail:
    """One batched detail mesh per articulated panel, with its source weights."""
    def __init__(self, source, fit):
        self.source,self.fit=source,fit
        self.vertices=[];self.faces=[];self.materials=[];self.indices=[]
        self.kd=KDTree(len(source.data.vertices))
        for v in source.data.vertices:self.kd.insert(v.co,v.index)
        self.kd.balance()
        self.groups={g.index:g.name for g in source.vertex_groups}

    def add(self,vertices,faces,mat):
        start=len(self.vertices)
        if mat not in self.materials:self.materials.append(mat)
        self.vertices.extend(vertices)
        self.faces.extend([tuple(start+i for i in face) for face in faces])
        self.indices.extend([self.materials.index(mat)]*len(faces))

    def weights(self,p):
        index=self.kd.find(p)[1]
        return {self.groups[g.group]:g.weight for g in self.source.data.vertices[index].groups}

    def tube(self,path,radius,mat,sides=5):
        vertices=[];faces=[]
        for i,p in enumerate(path):
            tangent=(Vector(path[min(i+1,len(path)-1)])-Vector(path[max(0,i-1)])).normalized()
            ref=Vector((1,0,0)) if abs(tangent.x)<.9 else Vector((0,1,0))
            n=tangent.cross(ref).normalized();b=tangent.cross(n)
            r=float(radius[i] if isinstance(radius,list) else radius)
            for j in range(sides):vertices.append(Vector(p)+r*(n*math.cos(math.tau*j/sides)+b*math.sin(math.tau*j/sides)))
        for i in range(len(path)-1):
            for j in range(sides):
                k=i*sides+j;nj=i*sides+(j+1)%sides
                faces.append((k,nj,nj+sides,k+sides))
        faces.extend([tuple(reversed(range(sides))),tuple((len(path)-1)*sides+j for j in range(sides))])
        self.add(vertices,faces,mat)

    def dome(self,center,axes,radii,mat,segments=8,rings=3):
        vertices=[];faces=[]
        for r in range(rings+1):
            phi=math.pi*(.01+.98*r/rings)
            for j in range(segments):
                a=math.tau*j/segments
                vertices.append(center+axes[0]*(radii[0]*math.sin(phi)*math.cos(a))+axes[1]*(radii[1]*math.sin(phi)*math.sin(a))+axes[2]*(radii[2]*math.cos(phi)))
        for r in range(rings):
            for j in range(segments):
                n=(j+1)%segments;faces.append((r*segments+j,r*segments+n,(r+1)*segments+n,(r+1)*segments+j))
        faces.extend([tuple(reversed(range(segments))),tuple(rings*segments+j for j in range(segments))])
        self.add(vertices,faces,mat)

    def finish(self):
        if not self.vertices:return
        obj=mesh_part(self.source.name+'_Fittings',self.vertices,self.faces,self.materials[0],self.fit,weights=self.weights,thickness=0)
        for mat in self.materials[1:]:obj.data.materials.append(mat)
        for p,index in zip(obj.data.polygons,self.indices):p.material_index=index
        # Rivets and piping are small on-screen; preserve the editable source
        # surfaces while collapsing redundant curved-detail triangles.
        bpy.context.view_layer.objects.active=obj
        decimate=obj.modifiers.new('CompactFittings','DECIMATE');decimate.ratio=.42
        bpy.ops.object.modifier_move_up(modifier=decimate.name)
        bpy.ops.object.modifier_apply(modifier=decimate.name)


def grid_sample(obj,u,v):
    rows,cols=int(obj['grid_rows']),int(obj['grid_cols'])
    r=min(rows-1,int(v*rows));c=min(cols-1,int(u*cols));tv=v*rows-r;tu=u*cols-c
    p00=obj.data.vertices[r*(cols+1)+c].co
    p01=obj.data.vertices[r*(cols+1)+c+1].co
    p10=obj.data.vertices[(r+1)*(cols+1)+c].co
    p11=obj.data.vertices[(r+1)*(cols+1)+c+1].co
    p=p00.lerp(p01,tu).lerp(p10.lerp(p11,tu),tv)
    n=(p01-p00).cross(p10-p00).normalized()
    # Choose the source surface normal; shell winding differs by panel orientation.
    native=obj.data.vertices[r*(cols+1)+c].normal
    if n.dot(native)<0:n=-n
    return p+n*.004,n


def beast(detail,center,xaxis,yaxis,normal,size,metal,dark):
    """Paired brows/eyes, muzzle, fangs, nose and curled mane in relief."""
    axes=[xaxis,yaxis,normal]
    point=lambda x,y,z=0:center+size*(xaxis*x+yaxis*y+normal*z)
    detail.dome(point(0,0),axes,(size*.92,size*.92,size*.07),dark,24,6)
    for sign in [-1,1]:
        for j in range(5):
            cy=.66-j*.29
            path=[point(sign*(.66+.14*math.cos(t)),cy+.15*math.sin(t),.12) for t in np.linspace(0,math.tau*1.05,20)]
            detail.tube(path,size*.065,metal)
        detail.dome(point(sign*.30,.10,.10),axes,(size*.22,size*.18,size*.12),dark)
        detail.dome(point(sign*.29,.10,.17),axes,(size*.115,size*.075,size*.07),metal)
        detail.tube([point(sign*.07,.22,.19),point(sign*.25,.40,.21),point(sign*.50,.34,.20),point(sign*.63,.48,.16)],size*.09,metal)
        detail.dome(point(sign*.19,-.30,.17),axes,(size*.25,size*.19,size*.14),metal)
        detail.tube([point(sign*.4,-.25,.19),point(sign*.43,-.43,.25),point(sign*.25,-.52,.28)],[size*.085,size*.055,.0007],metal)
        detail.tube([point(sign*.49,.5,.10),point(sign*.52,.76,.09),point(sign*.27,.58,.16)],size*.07,metal)
    detail.dome(point(0,.02,.24),axes,(size*.14,size*.20,size*.17),metal)
    detail.dome(point(0,-.13,.33),axes,(size*.18,size*.10,size*.08),dark)
    detail.tube([point(-.29,-.5,.14),point(0,-.59,.15),point(.29,-.5,.14)],size*.055,metal)
    path=[point(.93*math.cos(a),.93*math.sin(a),.05) for a in np.linspace(0,math.tau,60)]
    detail.tube(path,size*.047,metal)


def finish(fit,parts):
    leather_texture()
    bronze=material('AntiqueBrass',(.34,.19,.073),.77,.4)
    silver=bpy.data.materials['ChineseGear_Silver']
    silver.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.38
    dark=material('RecessedBronze',(.038,.025,.017),.6,.48)
    silver_dark=material('SilverPatina',(.055,.067,.078),.77,.48)
    edge=material('LeatherEdge',(.13,.049,.017),0,.65)
    for obj in parts:
        if not obj.name.startswith(ARMOR) or 'grid_rows' not in obj:continue
        obj.data.materials[0]=bpy.data.materials['ChineseGear_Leather']
        detail=Detail(obj,fit)
        if 'Cuirass' in obj.name or 'ShoulderYoke' in obj.name:continue
        # Geometric piping and rivets retain thickness from side views.
        for horizontal in [True,False]:
            for constant in [.035,.965]:
                path=[grid_sample(obj,t,constant)[0] if horizontal else grid_sample(obj,constant,t)[0] for t in np.linspace(.025,.975,24)]
                detail.tube(path,.0025,edge)
                for t in np.linspace(.06,.94,10 if horizontal else 8):
                    p,n=grid_sample(obj,t,constant) if horizontal else grid_sample(obj,constant,t)
                    tangent=n.cross(Vector((0,0,1)))
                    if tangent.length<.1:tangent=n.cross(Vector((1,0,0)))
                    tangent.normalize()
                    detail.dome(p+n*.001,[tangent,n.cross(tangent),n],(.0035,.0035,.0020),bronze,6,2)
        if 'SkirtPanel' in obj.name:
            for row in [.21,.40,.59,.78]:
                detail.tube([grid_sample(obj,t,row)[0] for t in np.linspace(.035,.965,20)],.0015,edge)
                for u in np.linspace(.10,.90,6):
                    p,n=grid_sample(obj,u,row)
                    tangent=n.cross(Vector((0,0,1))).normalized()
                    detail.dome(p,[tangent,n.cross(tangent),n],(.0028,.0028,.0018),bronze,6,2)
            for col in [.28,.50,.72]:
                detail.tube([grid_sample(obj,col,t)[0] for t in np.linspace(.04,.96,32)],.0009,edge)
        if 'ChestPanel' in obj.name:
            detail.tube([grid_sample(obj,.5,t)[0] for t in np.linspace(.04,.97,32)],.0025,edge)
            for v in [.25,.30,.35]:
                detail.tube([grid_sample(obj,t,v+.035*abs(t-.5))[0] for t in np.linspace(.04,.96,30)],.002,edge)
        if obj.name.endswith('Belt'):
            p,n=grid_sample(obj,0,.5)
            beast(detail,p+Vector((0,-.01,0)),Vector((1,0,0)),Vector((0,0,1)),Vector((0,-1,0)),.031,bronze,dark)
        detail.finish()
    for obj in parts:
        if not obj.name.startswith(HELMET) or 'CrownBand' not in obj.name:continue
        d=Detail(obj,fit)
        for u in [.15,.85]:
            d.tube([grid_sample(obj,u,v)[0] for v in np.linspace(.08,.97,40)],.0012,silver_dark)
            for v in np.linspace(.12,.9,6):
                p,n=grid_sample(obj,u,v)
                tangent=n.cross(Vector((1,0,0)))
                if tangent.length<.1:tangent=n.cross(Vector((0,1,0)))
                tangent.normalize()
                d.dome(p,[tangent,n.cross(tangent),n],(.0025,.0025,.0015),bronze,8,4)
        d.finish()
    # Rich brow crest sits on, and rises from, the actual helmet rim.
    rim=bpy.data.objects[HELMET+'BrowBand'];d=Detail(rim,fit)
    head=fit.bone('J_Bip_C_Head');front,_=grid_sample(rim,0,.6)
    vertices=[];faces=[]
    for row in range(5):
        for col in range(49):
            a=-.74+1.48*col/48
            p,n=grid_sample(rim,(a/math.tau)%1,.6)
            height=.013+.051*math.exp(-(a/.32)**2)+.011*(.5+.5*math.cos(a*21))
            vertices.append(p+Vector((0,.002,-.006+height*row/4)))
    for row in range(4):
        for col in range(48):
            i=row*49+col;faces.append((i,i+1,i+50,i+49))
    crest=mesh_part(HELMET+'EmbossedCrest',vertices,faces,silver_dark,fit,'J_Bip_C_Head',thickness=.004)
    for sign in [-1,1]:
        for k in range(3):
            cx=sign*(.022+k*.027);cz=.007+.014*(2-k)
            path=[]
            for t in np.linspace(0,math.tau*1.2,34):
                r=.014*(1-t/(math.tau*1.7))
                x=cx+sign*r*math.cos(t);z=cz+r*math.sin(t)
                p,_=grid_sample(rim,(math.asin(max(-.95,min(.95,x/.14)))/math.tau)%1,.6)
                path.append(p+Vector((0,-.004,z)))
            d.tube(path,.0026,silver,8)
    d.tube([front+Vector((.026*math.sin(a)*(1+.18*math.cos(3*a)),-.004,.037+.027*math.cos(a))) for a in np.linspace(0,math.tau,64)],.003,silver,8)
    d.finish()
    for side,sign in [('L',1),('R',-1)]:
        obj=bpy.data.objects[HELMET+'SideGuard_'+side];d=Detail(obj,fit)
        c=Vector((sign*(max(abs(v.co.x) for v in obj.data.vertices)+.003),head.y+.002,head.z+.080))
        beast(d,c,Vector((0,sign,0)),Vector((0,0,1)),Vector((sign,0,0)),.040,silver,silver_dark)
        d.finish()
    # Fine individual fibers replace the gray solid plume silhouette.
    plume=bpy.data.objects[HELMET+'WhitePlume'];d=Detail(plume,fit)
    top=max(v.co.z for v in bpy.data.objects[HELMET+'Dome'].data.vertices)
    rng=np.random.default_rng(807)
    hairmats=[material('Horsehair'+str(i),(.58+i*.055,.57+i*.055,.53+i*.06),0,.61) for i in range(5)]
    for strand in range(72):
        angle=rng.uniform(0,math.tau);spread=rng.uniform(.002,.026);length=rng.uniform(.86,1.12)
        path=[];radii=[]
        for t in np.linspace(0,1,21):
            spread_t=spread*math.sin(math.pi*.8*t)
            path.append(Vector((head.x+math.cos(angle)*spread_t,head.y+.005+.18*t+math.sin(angle)*spread_t,top+.014+.10*math.sin(math.pi*t)-.29*length*t*t)))
            radii.append(.00018+.00125*(1-t)**.6)
        d.tube(path,radii,hairmats[strand%len(hairmats)],5)
    d.finish()
    plume_final=bpy.data.objects[plume.name+'_Fittings']
    plume_final.shape_key_add(name='Basis')
    for name,axis in [('TailSway',0),('TailLift',2)]:
        key=plume_final.shape_key_add(name=name);key.slider_min=-1
        for vertex,point in zip(plume_final.data.vertices,key.data):
            influence=max(0,min(1,(vertex.co.y-head.y)/.19))**1.6
            point.co[axis]+=.023*influence
    keys=plume_final.data.shape_keys;keys.animation_data_create()
    # Merge two light secondary-motion channels with each published skeletal clip.
    import json
    metadata=json.loads((WORK.parent/f'standard_anime_{fit.sex}_character_pack.json').read_text(encoding='utf-8'))
    for name in metadata['animations']:
        if name=='T-Pose':continue
        source=bpy.data.actions.get(name)
        if source is None:raise RuntimeError('Plume skeletal action missing: '+name)
        first,last=map(int,source.frame_range)
        action=bpy.data.actions.new('MingguangPlume_'+name)
        for key_index,key_name in enumerate(['TailSway','TailLift']):
            curve=action.fcurves.new(data_path=f'key_blocks["{key_name}"].value')
            for frame in range(first,last+1):
                phase=math.tau*(frame-first)/max(1,last-first)
                value=(.8 if key_index==0 else .55)*math.sin(phase+key_index*.6)
                curve.keyframe_points.insert(frame,value,options={'FAST'}).interpolation='LINEAR'
        track=keys.animation_data.nla_tracks.new();track.name=name
        track.strips.new(name,first,action);track.mute=True
    bpy.data.objects.remove(plume,do_unlink=True)
    # Narrow chin strap uses a rounded V under the jaw, leaving the face open.
    obj=bpy.data.objects[HELMET+'AventailHem'];d=Detail(obj,fit)
    d.tube([head+Vector((x,-.046-.035*(1-abs(x)/.089),z)) for x,z in [(-.092,.055),(-.088,-.025),(-.063,-.074),(0,-.090),(.063,-.074),(.088,-.025),(.092,.055)]],.004,bpy.data.materials['ChineseGear_BlackLeather'],8)
    d.finish()
    print('CHINESE_GEAR_DETAIL_READY',fit.sex,flush=True)
