extends SceneTree
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const CrowdSite = preload("res://scripts/terrain_lab/crowd_site.gd")
var checks := 0
var failed := false
func _initialize() -> void: _run.call_deferred()
func need(ok: bool, label: String) -> bool:
 checks += 1
 if not ok: failed = true; push_error(label)
 return ok
func _run() -> void:
 if not need(DisplayServer.get_name() != "headless","GPU required"): quit(1); return
 root.size = Vector2i(1280,1920)
 root.content_scale_size = Vector2i(1280,1920)
 var out := "res://output/civilian_visual"
 DirAccess.make_dir_recursive_absolute(out)
 var scene := Node2D.new()
 root.add_child(scene)
 var bg := ColorRect.new()
 bg.size = Vector2(1280,1920); bg.color = Color("34454f")
 scene.add_child(bg)
 var appearances: Array = []
 for row: Dictionary in Atlas.Civilian.catalog():
  appearances.append(row.appearance)
 # Actual CrowdSite registration and original native kits, not a substitute kit builder.
 var owner := CrowdSite.new()
 root.add_child(owner)
 var native: RefCounted = ClassDB.instantiate(&"ArmyCrowd")
 if not need(native != null and native.setup(1,197),"native setup"): quit(1); return
 var flat := PackedByteArray(); flat.resize(32*32)
 var walkable := flat.duplicate(); walkable.fill(1)
 need(native.set_terrain(32,32,flat,walkable,flat,flat,flat),"native terrain")
 native.set_ai(false)
 var formation: int = native.add_formation(0,8.5,8.5,0.0,2,1.0,0,30.0)
 need(native.add_soldiers(formation,PackedInt64Array([100,101,102,103]),PackedInt32Array([1,1,1,1]),PackedByteArray([0,0,0,0]),PackedInt32Array([0,0,0,0])) == 0 and native.finalize(),"native four people")
 need(native.set_military_role(0,2) and native.set_military_role(1,2) and native.set_military_role(2,2) and native.set_military_role(3,2),"native civilian roles")
 owner.crowd = native
 need(TerrainArmy.load_combat_bake(),"original bake clocks")
 if not need(owner._register_kits(appearances),"actual CrowdSite and BatchView admission"): quit(1); return
 for index in appearances.size():
  var appearance: Dictionary = appearances[index]
  for slot: String in ["idle","walk","run","hit","knockback","down","unconscious","get_up"]:
   need(owner._clip_for(slot,appearance) == slot,"native civilian " + slot)
  need(owner._clip_for("attack",appearance).is_empty(),"combat slot not supplied")
 # Render all locomotion/direction combinations using the production Sprite facade.
 for index in appearances.size():
  for action_index in 3:
   var action: String = ["idle","walk","run"][action_index]
   for direction_index in 4:
    var direction: String = Atlas.Civilian.DIRECTIONS[direction_index]
    var frame := Atlas.frame(appearances[index],action,direction,0.17)
    if not need(not frame.is_empty(),"GPU frame"): continue
    var sprite := Sprite2D.new()
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    sprite.texture = frame.texture
    sprite.scale = Vector2.ONE * float(frame.map_scale)
    sprite.position = Vector2(150 + direction_index*300,145 + (index*3+action_index)*150) - Vector2(float(frame.anchor_offset.x),float(frame.anchor_offset.y))*float(frame.map_scale)
    scene.add_child(sprite)
    need(Atlas.apply_dye(sprite,appearances[index]),"production dye shader")
    var label := Label.new()
    label.text = "%s %s %s" % [Atlas.Civilian.catalog()[index].id,action,direction]
    label.position = Vector2(50 + direction_index*300,150+(index*3+action_index)*150)
    scene.add_child(label)
 for tick in 4: await process_frame
 await RenderingServer.frame_post_draw
 var image := root.get_texture().get_image()
 need(image != null and image.save_png(out + "/four_recipes_locomotion_four_directions.png") == OK,"GPU sheet saved")
 # Production CrowdSite MultiMesh nodes consume the real native packet.
 scene.hide()
 var layer := Node2D.new(); root.add_child(layer)
 layer.scale = Vector2.ONE * 3.0
 layer.position = Vector2(-1024,-1024)
 owner.lab = layer
 image = await _draw_packet(owner,native)
 need(image != null and image.save_png(out + "/native_crowdsite_batch.png") == OK,"actual CrowdSite GPU batch saved")
 # CIV-A3 (平民 C1c): the four work clips through CrowdSite's activity tracks and the native presentation override.
 need(owner._civilian_activity.has_kits(),"civilian work tracks registered by the real kit builder")
 var work := ["civilian_sit","civilian_fetch_water","civilian_lift","civilian_carry"]
 var tracks := PackedInt32Array()
 var ages := PackedFloat32Array()
 for index in 4:
  var kit := int(owner._kit_ids[index])
  need(owner._civilian_activity._tracks.has(kit) and owner._civilian_activity._tracks[kit].size() == 4,"four work clips on kit " + str(kit))
  tracks.append_array(owner._civilian_activity._tracks[kit][work[index]])
  ages.append([1.2,1.0,0.8,0.5][index])
 var plain: PackedFloat32Array = native.pack_frame(64.0,0.0)
 need(native.render_set_activity(PackedInt32Array([0,1,2,3]),tracks,ages,PackedByteArray([1,1,1,1])),"native takes the four work activities")
 var worked: PackedFloat32Array = native.pack_frame(64.0,0.0)
 need(plain != worked,"the work activity changes the native packet")
 image = await _draw_packet(owner,native)
 need(image != null and image.save_png(out + "/native_work_activity.png") == OK,"work activity GPU batch saved")
 need(native.render_set_activity(PackedInt32Array(),PackedInt32Array(),PackedFloat32Array(),PackedByteArray()) and native.pack_frame(64.0,0.0) == plain,"clearing the activity restores the original packet")
 var file := FileAccess.open(out + "/result.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"status":"FAIL" if failed else "PASS","checks":checks,"scope":"real CrowdSite kit/node and native packet; CIV-A3 work activity tracks through the native override"},"  ",true))
 print("CIV_VISUAL_", "FAIL" if failed else "PASS", " checks=",checks)
 quit(1 if failed else 0)

## The production CrowdSite MultiMesh nodes draw the native packet; returns the window image.
func _draw_packet(owner: Node, native: RefCounted) -> Image:
 for node: Variant in owner.nodes.values():
  if node is MultiMeshInstance2D: node.visible = false
 var buf: PackedFloat32Array = native.pack_frame(64.0,0.0)
 var spans: PackedInt32Array = native.row_spans()
 var bounds: PackedFloat32Array = native.row_bounds()
 need(not spans.is_empty(),"native packet nonempty")
 for offset in range(0,spans.size(),6):
  if spans[offset+1] < 0: continue
  var node: MultiMeshInstance2D = owner._node(spans[offset+5],spans[offset],spans[offset+1])
  node.multimesh.instance_count = spans[offset+4]
  var b := int(offset / 6.0) * 4
  var margin: float = owner.view._pages[spans[offset+1]].margin
  node.multimesh.custom_aabb = AABB(Vector3(bounds[b]-margin,bounds[b+1]-margin,-1.0),Vector3(bounds[b+2]-bounds[b]+2.0*margin,bounds[b+3]-bounds[b+1]+2.0*margin,2.0))
  RenderingServer.multimesh_set_buffer(node.multimesh.get_rid(),buf.slice(spans[offset+2]*12,(spans[offset+2]+spans[offset+4])*12))
  node.visible = true
 for tick in 4: await process_frame
 await RenderingServer.frame_post_draw
 return root.get_texture().get_image()
