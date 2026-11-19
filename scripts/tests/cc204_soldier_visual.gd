extends SceneTree
const Atlas=preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const CrowdSite=preload("res://scripts/terrain_lab/crowd_site.gd")
var failed:=false
var cases: Array=[]
var images: Array[String]=[]
func _initialize() -> void:_run.call_deferred()
func need(ok: bool,label: String) -> bool:
 if not ok:failed=true;push_error(label)
 return ok
func fixture() -> RefCounted:
 var native: RefCounted=ClassDB.instantiate(&"ArmyCrowd")
 if not need(native!=null and native.setup(1,197),"native setup"):return null
 var flat:=PackedByteArray();flat.resize(32*32)
 var walk:=flat.duplicate();walk.fill(1)
 if not need(native.set_terrain(32,32,flat,walk,flat,flat,flat),"native terrain"):return null
 native.set_ai(false)
 var formation: int=native.add_formation(0,8.5,8.5,0.0,1,1.0,0,30.0)
 if not need(native.add_soldiers(formation,PackedInt64Array([100]),PackedInt32Array([1]),PackedByteArray([0]),PackedInt32Array([0]))==0 and native.finalize(),"native person"):return null
 return native
func _run() -> void:
 if not need(DisplayServer.get_name()!="headless","GPU required"):quit(1);return
 root.size=Vector2i(1280,960);root.content_scale_size=Vector2i(1280,960)
 var args:=OS.get_cmdline_user_args()
 if args.size()!=2:quit(1);return
 var input: Array=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
 var out: String=args[1];DirAccess.make_dir_recursive_absolute(out)
 var army:=TerrainArmy.new();root.add_child(army);army.set_process(false)
 if not need(TerrainArmy.load_combat_bake() and army._load_baked_soldier(),"original base presentation"):quit(1);return
 var sheet:=Node2D.new();root.add_child(sheet)
 var live: Array[Node]=[]
 var n:=0;var sheet_index:=0
 for row: Dictionary in input:
  if not bool(row.crowd_admitted):continue
  var appearance: Dictionary=row.appearance
  Atlas._mixed_root=row.mixed_root;Atlas.refresh_female_sources()
  var owner:=CrowdSite.new();root.add_child(owner)
  var native:=fixture()
  if native==null:quit(1);return
  owner.crowd=native
  var accepted:=owner._register_kits([appearance])
  need(accepted,"real CrowdSite kit "+str(n))
  if not accepted:quit(1);return
  var layer:=Node2D.new();sheet.add_child(layer)
  var cell:=Vector2(float(n%4)*320.0,floorf(float(n%8)/4.0)*440.0)
  layer.scale=Vector2.ONE*1.5
  var state: PackedFloat64Array=native.get_soldier_state(0)
  layer.position=cell+Vector2(160,350)-Vector2(float(state[14]),float(state[15]))*64.0*1.5
  owner.lab=layer
  var buf: PackedFloat32Array=native.pack_frame(64.0,0.0)
  var spans: PackedInt32Array=native.row_spans();var bounds: PackedFloat32Array=native.row_bounds()
  need(not spans.is_empty(),"native packet "+str(n))
  for offset in range(0,spans.size(),6):
   if spans[offset+1]<0:continue
   var node: MultiMeshInstance2D=owner._node(spans[offset+5],spans[offset],spans[offset+1])
   node.multimesh.instance_count=spans[offset+4]
   var b:=int(offset/6.0)*4;var margin: float=owner.view._pages[spans[offset+1]].margin
   node.multimesh.custom_aabb=AABB(Vector3(bounds[b]-margin,bounds[b+1]-margin,-1),Vector3(bounds[b+2]-bounds[b]+margin*2,bounds[b+3]-bounds[b+1]+margin*2,2))
   RenderingServer.multimesh_set_buffer(node.multimesh.get_rid(),buf.slice(spans[offset+2]*12,(spans[offset+2]+spans[offset+4])*12))
   node.visible=true
  var label:=Label.new();sheet.add_child(label)
  label.position=cell+Vector2(8,365);label.size=Vector2(300,70);label.add_theme_font_size_override("font_size",13)
  label.text="%03d body=%d %s\n%s %s"%[n,int(appearance.body),"mounted" if appearance.mounted else "foot",str(appearance.parts.weapon),str(appearance.parts.armor)]
  live.append(owner)
  cases.append({"index":n,"appearance":appearance,"mixed_root":row.mixed_root,"real_crowdsite_kit":accepted,"native_packet_spans":spans.size()/6})
  n+=1
  if n%8==0:
   for tick in 3:await process_frame
   await RenderingServer.frame_post_draw
   var image:=root.get_texture().get_image();var image_path:=out+"/soldiers_%02d.png"%sheet_index
   need(image!=null and image.save_png(image_path)==OK,"GPU sheet")
   images.append(image_path);sheet_index+=1
   for node: Node in live:node.queue_free()
   live.clear();sheet.queue_free()
   for tick in 3:await process_frame
   sheet=Node2D.new();root.add_child(sheet)
 if n%8!=0:
  for tick in 3:await process_frame
  await RenderingServer.frame_post_draw
  var image:=root.get_texture().get_image();var image_path:=out+"/soldiers_%02d.png"%sheet_index
  need(image!=null and image.save_png(image_path)==OK,"last GPU sheet");images.append(image_path)
 var file:=FileAccess.open(out+"/result.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"status":"FAIL" if failed else "PASS","cases":cases,"images":images,"scope":"real original CrowdSite/BatchView/native kit and draw path for every originally crowd-admitted appearance; no gameplay/FPS claim"},"  ",true));file.close()
 for node: Node in live:node.queue_free()
 sheet.queue_free();army.queue_free()
 for tick in 3:await process_frame
 print("CC204_SOLDIER_VISUAL_", "FAIL" if failed else "PASS"," cases=",cases.size())
 quit(1 if failed else 0)
