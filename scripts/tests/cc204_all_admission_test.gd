extends SceneTree
const Atlas=preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const INPUT="res://scripts/tests/fixtures/cc204_supported_appearances.json"
var failures: Array[String]=[]
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
 var expected: Array=JSON.parse_string(FileAccess.get_file_as_string(INPUT))
 var results: Array=[]
 var original_sprite:=0;var original_crowd:=0;var new_sprite:=0;var new_crowd:=0
 for root_path: String in ["user://equipment_atlas/v1","res://output/site_siege_close_20261004/equipment_atlas_runtime"]:
  Atlas._mixed_root=root_path;Atlas.refresh_female_sources()
  var group: Array=[];var appearances: Array=[]
  for row: Dictionary in expected:
   if row.mixed_root==root_path:group.append(row);appearances.append(row.appearance)
  var admission:=Atlas.admit_crowd_appearances([],appearances)
  for n in group.size():
   var row: Dictionary=group[n];var appearance: Dictionary=row.appearance
   var mounted:=bool(appearance.get("mounted",false))
   var sprite:=SiteMountedSoldierAtlas.available(appearance) if mounted else Atlas.supports(appearance)
   var crowd: bool=SiteMountedSoldierAtlas.available(appearance) if mounted else n not in admission.optional_missing
   if row.supports:original_sprite+=1
   if row.crowd_admitted:original_crowd+=1
   if sprite:new_sprite+=1
   if crowd:new_crowd+=1
   if row.supports and not sprite:failures.append("lost Sprite "+str(results.size()))
   if row.crowd_admitted and not crowd:failures.append("lost crowd "+str(results.size()))
   results.append({"appearance":appearance,"mixed_root":root_path,"original_supports":row.supports,"original_crowd":row.crowd_admitted,"supports":sprite,"crowd_admitted":crowd})
 var out:="res://output/cc204_all_admission";DirAccess.make_dir_recursive_absolute(out)
 var file:=FileAccess.open(out+"/result.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"status":"PASS" if failures.is_empty() else "FAIL","original_sprite":original_sprite,"original_crowd":original_crowd,"new_sprite":new_sprite,"new_crowd":new_crowd,"results":results,"failures":failures},"  ",true));file.close()
 for failure: String in failures:push_error(failure)
 print("CC204_ALL_ADMISSION_", "PASS" if failures.is_empty() else "FAIL"," Sprite=",new_sprite,"/",original_sprite," crowd=",new_crowd,"/",original_crowd)
 quit(0 if failures.is_empty() else 1)
