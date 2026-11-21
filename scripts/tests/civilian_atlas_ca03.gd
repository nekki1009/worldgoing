extends SceneTree
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const Profile = Atlas.Civilian
var checks := 0
var failures: Array[String] = []
var cases: Array[Dictionary] = []
func _initialize() -> void: _run.call_deferred()
func need(ok: bool, label: String) -> void:
 checks += 1
 cases.append({"case":label,"pass":ok})
 if not ok: failures.append(label); push_error(label)
func reset() -> void: Atlas.refresh_female_sources()
func write(path: String, data: PackedByteArray) -> void:
 var file := FileAccess.open(path,FileAccess.WRITE)
 file.store_buffer(data)
func corrupt(path: String, value: Variant, appearance: Dictionary, label: String) -> void:
 var original := FileAccess.get_file_as_bytes(path)
 write(path,JSON.stringify(value,"  ",true).to_utf8_buffer())
 reset()
 need(not Atlas.supports(appearance),label)
 write(path,original)
 reset()
func _run() -> void:
 var source_id := Profile.source_namespace(Profile.fingerprints())
 for row: Dictionary in Profile.catalog():
  var appearance: Dictionary = row.appearance
  reset()
  need(Atlas.supports(appearance),row.id + " supports")
  need(not Atlas.dye_entry(appearance).is_empty(),row.id + " dye")
  var admission := Atlas.admit_crowd_appearances([appearance])
  need(bool(admission.ok),row.id + " crowd admission")
  var recipe := Atlas.civilian_recipe(appearance)
  need(not recipe.is_empty(),row.id + " exact recipe")
  if recipe.is_empty(): continue
  need(recipe.sequences.size() == 48,row.id + " 12x4 sequences (CIV-A3 work clips included)")
  var directory := Profile.ROOT + "/" + source_id + "/" + str(Profile.plan(appearance).key)
  var path := directory + "/manifest.json"
  var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
  need(manifest.frames.size() == Profile.frames() and Profile.frames() == 416,row.id + " 416 frames")
  for clip: Dictionary in Profile.Clips.ALL:
   for direction: String in Profile.DIRECTIONS:
    var sequence: Array = recipe.sequences[clip.id + "|" + direction]
    need(sequence.size() == int(clip.samples),row.id + " sample count " + clip.id + direction)
    for frame: Dictionary in sequence:
     var result := Atlas.frame(appearance,clip.id,direction,float(frame.sample_time))
     need(not result.is_empty() and int(result.frame) == int(frame.frame) and result.anchor_offset == frame.anchor_offset,row.id + " time/anchor " + clip.id + direction + str(frame.frame))
  var other := appearance.duplicate(true)
  other.parts.hair = "none"
  need(not Atlas.supports(other),row.id + " unbaked hair rejected")
  need(Atlas.frame(appearance,"attack_unarmed","down",0.0).is_empty(),row.id + " unsupported clip rejected")
  for field: String in ["color","mask"]:
   var dye: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory + "/dye.json"))
   var image_path: String = manifest.pages[0].path if field == "color" else dye.mask_path
   var held := image_path + ".negative"
   need(DirAccess.rename_absolute(image_path,held) == OK,"hold " + field)
   reset(); need(not Atlas.supports(appearance),row.id + " missing " + field)
   need(DirAccess.rename_absolute(held,image_path) == OK,"restore " + field)
  for kind: String in ["clip","direction","count","time","anchor","source","hash","dimensions"]:
   var broken := manifest.duplicate(true)
   match kind:
    "clip": broken.clips.remove_at(0)
    "direction": broken.directions.reverse()
    "count": broken.frames.pop_back()
    "time": broken.frames[1].sample_time = -1.0
    "anchor": broken.frames[0].erase("anchor_offset")
    "source": broken.source_fingerprints["res://scripts/ui/human_character_3d_editor.gd"] = "00000000000000000000000000000000"
    "hash": broken.pages[0].png_md5 = "00000000000000000000000000000000"
    "dimensions": broken.pages[0].height += 1
   corrupt(path,broken,appearance,row.id + " corrupt " + kind)
  var dye_path := directory + "/dye.json"
  var dye_record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dye_path))
  for kind: String in ["mask_hash","mask_dimensions","dye_source"]:
   var broken := dye_record.duplicate(true)
   match kind:
    "mask_hash": broken.mask_md5 = "00000000000000000000000000000000"
    "mask_dimensions": broken.width += 1
    "dye_source": broken.source_fingerprints["res://scripts/ui/equipment_dye.gd"] = "00000000000000000000000000000000"
   corrupt(dye_path,broken,appearance,row.id + " corrupt " + kind)
  reset(); need(Atlas.supports(appearance),row.id + " restored positive")
 var out := "res://output/civilian_ca03"
 DirAccess.make_dir_recursive_absolute(out)
 var result := {"checks":checks,"failures":failures,"cases":cases,"source_id":source_id,"status":"PASS" if failures.is_empty() else "FAIL"}
 write(out + "/result.json",JSON.stringify(result,"  ",true).to_utf8_buffer())
 print("CIV_CA03_",result.status," checks=",checks)
 quit(0 if failures.is_empty() else 1)
