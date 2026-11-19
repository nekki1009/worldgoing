extends "res://scripts/terrain_lab/terrain_army_atlas_capture.gd"
## Keep the original projection, sampling, material mask and lossless checks.
## CIV-A3: the four civilian work clips are built on the editor's own skeleton (civilian_work_clips.gd) and registered
## in its AnimationPlayer for this capture only; the editor, packs and soldier baker are not edited.
const CivilianProfile = preload("res://scripts/terrain_lab/terrain_army_civilian_atlas.gd")
const CivilianClips = preload("res://scripts/terrain_lab/civilian_atlas_clips.gd")
const Work = preload("res://scripts/terrain_lab/civilian_work_clips.gd")

func _capture(plan: Dictionary, output: String, sources: Dictionary, dye_sources: Dictionary) -> bool:
 if plan != CivilianProfile.plan(plan.appearance): return _reject("Not an exact civilian plan")
 if not await super._capture(plan, output, sources, dye_sources): return false
 var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output + "/manifest.json"))
 manifest["kind"] = "terrain_army_civilian_recipe"
 # The carry clip ends one sample short of its 1.0 s cycle (civilian_work_clips.gd), so the manifest keeps the reader's
 # one-shot spacing (duration 0.875, samples 0..0.875). Whoever plays it as a loop uses Work.DURATIONS (1.0 s).
 if not _write_json(output + "/manifest.json", manifest): return false
 var dye: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output + "/dye.json"))
 dye["source_manifest_md5"] = FileAccess.get_md5(output + "/manifest.json")
 return _write_json(output + "/dye.json", dye)

## Same rules as the base, against the civilian clip table (phase one keeps the original baker's samples and rates).
static func _valid_plan(plan: Dictionary) -> bool:
 if not plan.get("appearance") is Dictionary or not HumanCharacter3DEditor.valid_appearance(plan.appearance): return false
 if plan.appearance.has("equipment_dyes") or plan.appearance.get("mounted") != false or not _hex(str(plan.get("key", "")), 64): return false
 if plan.key != JSON.stringify(plan.appearance, "", true).sha256_text(): return false
 if not _hex(str(plan.get("source_manifest_md5", "")), 32) or not plan.get("clips") is Array or plan.clips.is_empty() or plan.get("directions") != Baker.DIRECTIONS: return false
 if plan.clips != JSON.parse_string(JSON.stringify(CivilianClips.ALL)): return false
 var count := 0
 for clip: Dictionary in CivilianClips.ALL:
  if not clip.id.begins_with("civilian_"):
   var original := {}
   for base: Dictionary in Baker.CLIPS:
    if base.id == clip.id: original = base
   if original.is_empty() or clip.samples != original.samples or clip.rate != original.rate: return false
  count += int(clip.samples) * Baker.DIRECTIONS.size()
 return plan.get("recipe_total") == count

## Both passes (colour and mask) build the editor here; register the work clips right after.
func _make_editor(appearance: Dictionary, masks: bool) -> bool:
 if not super._make_editor(appearance, masks): return false
 var player := _editor.animation_player
 if player == null: return _reject("Editor has no AnimationPlayer")
 var model := player.get_node(player.root_node)
 var skeletons := model.find_children("*", "Skeleton3D", true, false)
 if skeletons.size() != 1: return _reject("Civilian work clips need exactly one skeleton")
 var clips := Work.build(player, skeletons[0], str(model.get_path_to(skeletons[0])))
 if clips.size() != Work.IDS.size(): return _reject("Civilian work clip build failed")
 var library := player.get_animation_library(&"")
 for id: String in Work.IDS:
  if library.has_animation(id): return _reject("Pack already has " + id)
  library.add_animation(id, clips[id])
  _editor.animation_option.add_item(id)
  _editor.animation_option.set_item_metadata(_editor.animation_option.item_count - 1, id)
  _editor._available_animation_ids[StringName(id)] = true
 return _alive()
