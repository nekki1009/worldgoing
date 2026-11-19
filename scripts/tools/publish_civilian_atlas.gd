extends SceneTree
const Profile = preload("res://scripts/terrain_lab/terrain_army_civilian_atlas.gd")
const Dye = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const Capture = preload("res://scripts/terrain_lab/civilian_atlas_capture.gd")
func _initialize() -> void: _run.call_deferred()
func _write(path: String, value: Variant) -> bool:
 var file := FileAccess.open(path, FileAccess.WRITE)
 if file == null: return false
 file.store_string(JSON.stringify(value,"  ",true) + "\n")
 return true
func _relocate(value: Variant, old: String, target: String) -> Variant:
 if value is String: return value.replace(old,target)
 if value is Array:
  for i in value.size(): value[i] = _relocate(value[i],old,target)
 if value is Dictionary:
  for key: Variant in value: value[key] = _relocate(value[key],old,target)
 return value
func _run() -> void:
 var sources := Profile.fingerprints()
 var dyes := Dye.fingerprints()
 if sources.is_empty() or dyes.is_empty(): quit(1); return
 var source_id := Profile.source_namespace(sources)
 var stage := "res://output/civilian_publish/" + source_id
 var target := Profile.ROOT + "/" + source_id
 if DirAccess.dir_exists_absolute(stage) or DirAccess.dir_exists_absolute(target):
  push_error("Fresh staging and source_id required"); quit(1); return
 DirAccess.make_dir_recursive_absolute(stage)
 _write(stage + "/frozen_sources.json", {"sources":sources,"dye_sources":dyes,"source_id":source_id})
 var rows: Array = []
 var capture := Capture.new()
 root.add_child(capture)
 var all_recipes := "--all-recipes" in OS.get_cmdline_user_args()
 for row: Dictionary in Profile.catalog():
  if not all_recipes and int(row.appearance.body) != 0: continue
  var plan := Profile.plan(row.appearance)
  var directory := stage + "/" + str(plan.key)
  print("CIV_CAPTURE_BEGIN ",row.id)
  if not await capture.capture(plan,directory,sources,dyes):
   push_error("Civilian capture failed: " + str(capture.error)); quit(1); return
  rows.append({"id":row.id,"key":plan.key,"appearance":row.appearance})
 if sources != Profile.fingerprints() or dyes != Dye.fingerprints():
  push_error("Frozen source epoch changed"); quit(1); return
 for row: Dictionary in rows:
  var directory := stage + "/" + str(row.key)
  var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory + "/manifest.json"))
  manifest = _relocate(manifest,stage,target)
  if not _write(directory + "/manifest.json",manifest): quit(1); return
  var dye: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory + "/dye.json"))
  dye = _relocate(dye,stage,target)
  dye["source_manifest_md5"] = FileAccess.get_md5(directory + "/manifest.json")
  if not _write(directory + "/dye.json",dye): quit(1); return
 if not _write(stage + "/catalog.json",{"profile":Profile.PROFILE,"phase":1,"source_id":source_id,"recipes":rows,"omitted":["civilian_carry","civilian_lift","civilian_sit","civilian_fetch_water"]}): quit(1); return
 DirAccess.make_dir_recursive_absolute(Profile.ROOT)
 if DirAccess.rename_absolute(stage,target) != OK: quit(1); return
 print("CIV_PUBLISH_PASS ",target)
 quit(0)
